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

#ifndef COMMON_RUBYBINDINGS_H
#define COMMON_RUBYBINDINGS_H

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/string.h>
#include <mruby/variable.h>
#include <stdexcept>
#include <string>
#include "nextpnr.h"
#include "rubycontainers.h"
#include "rubywrappers.h"

NEXTPNR_NAMESPACE_BEGIN

// Returns the global mruby interpreter state (valid between init_ruby/deinit_ruby)
mrb_state *get_ruby_state();

void init_ruby(const char *executable);
void deinit_ruby();
void execute_ruby_file(const char *ruby_file);

template <typename Tn> void ruby_export_global(const char *name, Tn &x)
{
    mrb_state *mrb = get_ruby_state();
    if (!mrb)
        return;
    mrb_value obj = RubyConversion::wrap_object(mrb, x);
    std::string gname = std::string("$") + name;
    mrb_gv_set(mrb, mrb_intern_cstr(mrb, gname.c_str()), obj);
}

// Default IdString conversions
namespace RubyConversion {

template <> struct string_converter<IdString>
{
    inline IdString from_str(Context *ctx, const std::string &name) { return ctx->id(name); }
    inline std::string to_str(Context *ctx, IdString id) { return id.str(ctx); }
};

template <> struct string_converter<const IdString>
{
    inline IdString from_str(Context *ctx, const std::string &name) { return ctx->id(name); }
    inline std::string to_str(Context *ctx, IdString id) { return id.str(ctx); }
};

template <> struct string_converter<IdStringList>
{
    IdStringList from_str(Context *ctx, const std::string &name) { return IdStringList::parse(ctx, name); }
    std::string to_str(Context *ctx, const IdStringList &id) { return id.str(ctx); }
};

template <> struct string_converter<const IdStringList>
{
    IdStringList from_str(Context *ctx, const std::string &name) { return IdStringList::parse(ctx, name); }
    std::string to_str(Context *ctx, const IdStringList &id) { return id.str(ctx); }
};

} // namespace RubyConversion

NEXTPNR_NAMESPACE_END

#endif /* COMMON_RUBYBINDINGS_H */
