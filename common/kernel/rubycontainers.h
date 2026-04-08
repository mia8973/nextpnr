/*
 *  nextpnr -- Next Generation Place and Route
 *
 *  Copyright (C) 2018  Claire Xenia Wolf <claire@yosyshq.com>
 *  Copyright (C) 2018  gatecat <gatecat@ds0.me>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#ifndef COMMON_RUBYCONTAINERS_H
#define COMMON_RUBYCONTAINERS_H

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/hash.h>
#include <mruby/proc.h>
#include <mruby/string.h>
#include <mruby/value.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include "nextpnr.h"
#include "rubywrappers.h"

NEXTPNR_NAMESPACE_BEGIN

namespace RubyConversion {

// -------------------------------------------------------
// Range wrapper: exposes C++ begin/end ranges as Ruby Enumerable
// Usage: register_range_class<MyRange, value_conv>(mrb, "MyRange");
// In Ruby: range.each { |item| ... }
// -------------------------------------------------------

template <typename RangeT, typename value_conv> struct range_wrapper
{
    typedef decltype(std::declval<RangeT>().begin()) iterator_t;
    typedef ContextualWrapper<RangeT> wrapped_range;

    struct IterData
    {
        Context *ctx;
        iterator_t current;
        iterator_t end;
    };

    static mrb_value each(mrb_state *mrb, mrb_value self)
    {
        mrb_value block;
        mrb_get_args(mrb, "&", &block);

        auto *data = static_cast<ContextObjectData<RangeT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<RangeT>>::value));
        if (!data)
            return mrb_nil_value();

        for (auto it = data->ptr->begin(); it != data->ptr->end(); ++it) {
            try {
                mrb_value elem = wrap_range_item(mrb, data->ctx, *it);
                mrb_yield(mrb, block, elem);
            } catch (bad_wrap &) {
                // skip nil entries
            }
        }
        return self;
    }

    static mrb_value inspect(mrb_state *mrb, mrb_value self)
    {
        auto *data = static_cast<ContextObjectData<RangeT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<RangeT>>::value));
        std::ostringstream ss;
        ss << "[";
        bool first = true;
        if (data) {
            for (auto &item : *data->ptr) {
                if (!first)
                    ss << ", ";
                try {
                    value_conv conv;
                    ss << "\"" << conv(data->ctx, item) << "\"";
                } catch (bad_wrap &) {
                }
                first = false;
            }
        }
        ss << "]";
        return mrb_str_new_cstr(mrb, ss.str().c_str());
    }

    // Helper to create item mrb_value; specialised below
    static mrb_value wrap_range_item(mrb_state *mrb, Context *ctx, decltype(*std::declval<iterator_t>()) item)
    {
        value_conv conv;
        auto result = conv(ctx, item);
        return to_mrb_value(mrb, result);
    }

    static mrb_value to_mrb_value(mrb_state *mrb, const std::string &s)
    {
        return mrb_str_new_cstr(mrb, s.c_str());
    }

    static void wrap(mrb_state *mrb, const char *class_name)
    {
        struct RClass *cls = mrb_define_class(mrb, class_name, mrb->object_class);
        MRB_SET_INSTANCE_TT(cls, MRB_TT_DATA);
        mrb_define_method(mrb, cls, "each", each, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "inspect", inspect, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "to_s", inspect, MRB_ARGS_NONE());
    }
};

// -------------------------------------------------------
// Map wrapper: exposes C++ dict-like containers with
// Ruby .each { |k, v| }, .[], .length, .key?
// -------------------------------------------------------

template <typename MapT, typename value_conv> struct map_wrapper
{
    typedef typename std::remove_cv<typename std::remove_reference<typename MapT::key_type>::type>::type K;
    typedef typename MapT::mapped_type V;
    typedef typename MapT::value_type KV;

    static mrb_value each(mrb_state *mrb, mrb_value self)
    {
        mrb_value block;
        mrb_get_args(mrb, "&", &block);

        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_nil_value();

        for (auto &kv : *data->ptr) {
            std::string key_str = string_converter<K>().to_str(data->ctx, kv.first);
            mrb_value key = mrb_str_new_cstr(mrb, key_str.c_str());
            mrb_value val = wrap_value(mrb, data->ctx, kv.second);
            mrb_value pair[2] = {key, val};
            mrb_value ary = mrb_ary_new_from_values(mrb, 2, pair);
            mrb_yield(mrb, block, ary);
        }
        return self;
    }

    static mrb_value each_pair(mrb_state *mrb, mrb_value self) { return each(mrb, self); }

    static mrb_value getitem(mrb_state *mrb, mrb_value self)
    {
        mrb_value key_v;
        mrb_get_args(mrb, "o", &key_v);

        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_nil_value();

        std::string key_str = mrb_str_to_cstr(mrb, mrb_any_to_s(mrb, key_v));
        K k = string_converter<K>().from_str(data->ctx, key_str);
        auto it = data->ptr->find(k);
        if (it == data->ptr->end())
            return mrb_nil_value();
        return wrap_value(mrb, data->ctx, it->second);
    }

    static mrb_value length(mrb_state *mrb, mrb_value self)
    {
        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_fixnum_value(0);
        return mrb_fixnum_value((mrb_int)data->ptr->size());
    }

    static mrb_value has_key(mrb_state *mrb, mrb_value self)
    {
        mrb_value key_v;
        mrb_get_args(mrb, "o", &key_v);
        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_false_value();
        std::string key_str = mrb_str_to_cstr(mrb, mrb_any_to_s(mrb, key_v));
        K k = string_converter<K>().from_str(data->ctx, key_str);
        return mrb_bool_value(data->ptr->count(k) > 0);
    }

    static mrb_value wrap_value(mrb_state *mrb, Context *ctx, V &v)
    {
        value_conv conv;
        auto result = conv(ctx, v);
        return to_mrb_val(mrb, result);
    }

    static mrb_value to_mrb_val(mrb_state *mrb, const std::string &s) { return mrb_str_new_cstr(mrb, s.c_str()); }
    template <typename R> static mrb_value to_mrb_val(mrb_state *mrb, R &r)
    {
        // handled by specialized wrap_object
        return wrap_object(mrb, r);
    }

    static void wrap(mrb_state *mrb, const char *class_name)
    {
        struct RClass *cls = mrb_define_class(mrb, class_name, mrb->object_class);
        MRB_SET_INSTANCE_TT(cls, MRB_TT_DATA);
        mrb_define_method(mrb, cls, "each", each, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "each_pair", each_pair, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "[]", getitem, MRB_ARGS_REQ(1));
        mrb_define_method(mrb, cls, "length", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "size", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "key?", has_key, MRB_ARGS_REQ(1));
        mrb_define_method(mrb, cls, "include?", has_key, MRB_ARGS_REQ(1));
    }
};

// -------------------------------------------------------
// Map wrapper for unique_ptr values
// -------------------------------------------------------

template <typename MapT, typename value_conv> struct map_wrapper_uptr
{
    typedef typename std::remove_cv<typename std::remove_reference<typename MapT::key_type>::type>::type K;
    typedef typename MapT::mapped_type::element_type V;
    typedef typename MapT::value_type KV;

    static mrb_value each(mrb_state *mrb, mrb_value self)
    {
        mrb_value block;
        mrb_get_args(mrb, "&", &block);

        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_nil_value();

        for (auto &kv : *data->ptr) {
            std::string key_str = string_converter<K>().to_str(data->ctx, kv.first);
            mrb_value key = mrb_str_new_cstr(mrb, key_str.c_str());
            mrb_value val = wrap_object(mrb, data->ctx, kv.second.get());
            mrb_value pair[2] = {key, val};
            mrb_value ary = mrb_ary_new_from_values(mrb, 2, pair);
            mrb_yield(mrb, block, ary);
        }
        return self;
    }

    static mrb_value each_pair(mrb_state *mrb, mrb_value self) { return each(mrb, self); }

    static mrb_value getitem(mrb_state *mrb, mrb_value self)
    {
        mrb_value key_v;
        mrb_get_args(mrb, "o", &key_v);

        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_nil_value();

        std::string key_str = mrb_str_to_cstr(mrb, mrb_any_to_s(mrb, key_v));
        K k = string_converter<K>().from_str(data->ctx, key_str);
        auto it = data->ptr->find(k);
        if (it == data->ptr->end())
            return mrb_nil_value();
        return wrap_object(mrb, data->ctx, it->second.get());
    }

    static mrb_value length(mrb_state *mrb, mrb_value self)
    {
        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_fixnum_value(0);
        return mrb_fixnum_value((mrb_int)data->ptr->size());
    }

    static mrb_value has_key(mrb_state *mrb, mrb_value self)
    {
        mrb_value key_v;
        mrb_get_args(mrb, "o", &key_v);
        auto *data = static_cast<ContextObjectData<MapT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<MapT>>::value));
        if (!data)
            return mrb_false_value();
        std::string key_str = mrb_str_to_cstr(mrb, mrb_any_to_s(mrb, key_v));
        K k = string_converter<K>().from_str(data->ctx, key_str);
        return mrb_bool_value(data->ptr->count(k) > 0);
    }

    static void wrap(mrb_state *mrb, const char *class_name)
    {
        struct RClass *cls = mrb_define_class(mrb, class_name, mrb->object_class);
        MRB_SET_INSTANCE_TT(cls, MRB_TT_DATA);
        mrb_define_method(mrb, cls, "each", each, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "each_pair", each_pair, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "[]", getitem, MRB_ARGS_REQ(1));
        mrb_define_method(mrb, cls, "length", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "size", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "key?", has_key, MRB_ARGS_REQ(1));
    }
};

// -------------------------------------------------------
// Pool/set wrapper (expose as an iterable)
// -------------------------------------------------------

template <typename SetT, typename value_conv> struct set_wrapper
{
    typedef typename SetT::value_type V;

    static mrb_value each(mrb_state *mrb, mrb_value self)
    {
        mrb_value block;
        mrb_get_args(mrb, "&", &block);

        auto *data = static_cast<ContextObjectData<SetT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<SetT>>::value));
        if (!data)
            return mrb_nil_value();

        for (auto &item : *data->ptr) {
            try {
                value_conv conv;
                auto result = conv(data->ctx, item);
                mrb_value elem = mrb_str_new_cstr(mrb, result.c_str());
                mrb_yield(mrb, block, elem);
            } catch (bad_wrap &) {
            }
        }
        return self;
    }

    static mrb_value length(mrb_state *mrb, mrb_value self)
    {
        auto *data = static_cast<ContextObjectData<SetT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<SetT>>::value));
        if (!data)
            return mrb_fixnum_value(0);
        return mrb_fixnum_value((mrb_int)data->ptr->size());
    }

    static void wrap(mrb_state *mrb, const char *class_name)
    {
        struct RClass *cls = mrb_define_class(mrb, class_name, mrb->object_class);
        MRB_SET_INSTANCE_TT(cls, MRB_TT_DATA);
        mrb_define_method(mrb, cls, "each", each, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "length", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "size", length, MRB_ARGS_NONE());
    }
};

// -------------------------------------------------------
// Indexed store wrapper (expose as an iterable array-like)
// -------------------------------------------------------

template <typename StoreT, typename value_conv> struct indexed_store_wrapper
{
    typedef decltype(std::declval<StoreT>().begin()) iterator_t;

    static mrb_value each(mrb_state *mrb, mrb_value self)
    {
        mrb_value block;
        mrb_get_args(mrb, "&", &block);

        auto *data = static_cast<ContextObjectData<StoreT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<StoreT>>::value));
        if (!data)
            return mrb_nil_value();

        for (auto it = data->ptr->begin(); it != data->ptr->end(); ++it) {
            try {
                value_conv conv;
                mrb_value elem = wrap_object(mrb, conv(data->ctx, *it));
                mrb_yield(mrb, block, elem);
            } catch (bad_wrap &) {
            }
        }
        return self;
    }

    static mrb_value length(mrb_state *mrb, mrb_value self)
    {
        auto *data = static_cast<ContextObjectData<StoreT> *>(
                mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<StoreT>>::value));
        if (!data)
            return mrb_fixnum_value(0);
        return mrb_fixnum_value((mrb_int)data->ptr->capacity());
    }

    static void wrap(mrb_state *mrb, const char *class_name)
    {
        struct RClass *cls = mrb_define_class(mrb, class_name, mrb->object_class);
        MRB_SET_INSTANCE_TT(cls, MRB_TT_DATA);
        mrb_define_method(mrb, cls, "each", each, MRB_ARGS_BLOCK());
        mrb_define_method(mrb, cls, "length", length, MRB_ARGS_NONE());
        mrb_define_method(mrb, cls, "size", length, MRB_ARGS_NONE());
    }
};

// -------------------------------------------------------
// Helper: wrap an AttrMap (dict<IdString, Property>)
// that yields [key_str, value_str] pairs
// -------------------------------------------------------

} // namespace RubyConversion

NEXTPNR_NAMESPACE_END

#endif /* COMMON_RUBYCONTAINERS_H */
