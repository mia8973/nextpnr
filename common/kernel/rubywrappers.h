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
 *  OR in CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#ifndef RUBYWRAPPERS_H
#define RUBYWRAPPERS_H

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/hash.h>
#include <mruby/string.h>
#include <mruby/value.h>
#include <mruby/variable.h>
#include <stdexcept>
#include <string>
#include <utility>
#include "nextpnr.h"

NEXTPNR_NAMESPACE_BEGIN

namespace RubyConversion {

// ContextualWrapper: pairs a C++ object with its Context*
template <typename T> struct ContextualWrapper
{
    Context *ctx;
    T base;
    ContextualWrapper(Context *c, T x) : ctx(c), base(x) {}
    operator T() { return base; }
    typedef T base_type;
};

// Helper to get Context* from wrapped or unwrapped types
template <typename T> struct WrapIfNotContext
{
    typedef ContextualWrapper<T> maybe_wrapped_t;
};
template <> struct WrapIfNotContext<Context>
{
    typedef Context maybe_wrapped_t;
};

template <typename T> inline Context *get_ctx(typename WrapIfNotContext<T>::maybe_wrapped_t &wrp)
{
    return wrp.ctx;
}
template <> inline Context *get_ctx<Context>(Context &ctx) { return &ctx; }

template <typename T> inline T &get_base(typename WrapIfNotContext<T>::maybe_wrapped_t &wrp) { return wrp.base; }
template <> inline Context &get_base<Context>(Context &ctx) { return ctx; }

// Dummy converter interface
template <typename T> struct string_converter;

class bad_wrap
{
};

// Conversion action types
template <typename T> struct pass_through
{
    inline T operator()(Context *, T x) { return x; }
    using ret_type = T;
    using arg_type = T;
};

template <typename T> struct wrap_context
{
    inline ContextualWrapper<T> operator()(Context *ctx, T x) { return ContextualWrapper<T>(ctx, x); }
    using arg_type = T;
    using ret_type = ContextualWrapper<T>;
};

template <typename T> struct unwrap_context
{
    inline T operator()(Context *, ContextualWrapper<T> x) { return x.base; }
    using ret_type = T;
    using arg_type = ContextualWrapper<T>;
};

template <typename T> struct conv_from_str
{
    inline T operator()(Context *ctx, const std::string &x) { return string_converter<T>().from_str(ctx, x); }
    using ret_type = T;
    using arg_type = std::string;
};

template <typename T> struct conv_to_str
{
    inline std::string operator()(Context *ctx, T x) { return string_converter<T>().to_str(ctx, x); }
    using ret_type = std::string;
    using arg_type = T;
};

template <typename T> struct deref_and_wrap
{
    inline ContextualWrapper<T &> operator()(Context *ctx, T *x)
    {
        if (x == nullptr)
            throw bad_wrap();
        return ContextualWrapper<T &>(ctx, *x);
    }
    using arg_type = T *;
    using ret_type = ContextualWrapper<T &>;
};

template <typename T> struct addr_and_unwrap
{
    inline T *operator()(Context *, ContextualWrapper<T &> x) { return &(x.base); }
    using arg_type = ContextualWrapper<T &>;
    using ret_type = T *;
};

// -------------------------------------------------------
// mruby type registration helpers
// -------------------------------------------------------

// Data type descriptor for mruby (no-op free: C++ manages lifetime)
template <typename T> struct RubyDataType
{
    static mrb_data_type value;
};
template <typename T> mrb_data_type RubyDataType<T>::value = {typeid(T).name(), [](mrb_state *, void *) {}};

// Storage struct for context+object pairs
template <typename T> struct ContextObjectData
{
    Context *ctx;
    T *ptr;
};

// Allocate an mruby object wrapping a C++ pointer
template <typename T> mrb_value make_ruby_obj(mrb_state *mrb, struct RClass *cls, Context *ctx, T *ptr)
{
    auto *data = new ContextObjectData<T>{ctx, ptr};
    mrb_value obj = mrb_obj_value(mrb_data_object_alloc(mrb, cls, data, &RubyDataType<ContextObjectData<T>>::value));
    // Set up free to delete the wrapper (not the C++ object)
    RubyDataType<ContextObjectData<T>>::value.dfree = [](mrb_state *, void *p) {
        delete static_cast<ContextObjectData<T> *>(p);
    };
    return obj;
}

template <typename T> ContextObjectData<T> *get_ruby_data(mrb_state *mrb, mrb_value self)
{
    return static_cast<ContextObjectData<T> *>(
            mrb_data_get_ptr(mrb, self, &RubyDataType<ContextObjectData<T>>::value));
}

// Generic wrapper: converts a C++ value to mruby value
// Specializations defined per type in rubybindings.cc
template <typename T> mrb_value wrap_object(mrb_state *mrb, T &x);
template <typename T> mrb_value wrap_object(mrb_state *mrb, T *x);

// Convert mrb_value string to std::string
inline std::string mrb_to_str(mrb_state *mrb, mrb_value v)
{
    return std::string(mrb_str_to_cstr(mrb, mrb_any_to_s(mrb, v)));
}

// Create mrb string from std::string
inline mrb_value str_to_mrb(mrb_state *mrb, const std::string &s)
{
    return mrb_str_new_cstr(mrb, s.c_str());
}

} // namespace RubyConversion

NEXTPNR_NAMESPACE_END

#endif /* RUBYWRAPPERS_H */
