#ifndef NO_RUBY

#include <mruby.h>
#include <mruby/string.h>
#include "nextpnr.h"

NEXTPNR_NAMESPACE_BEGIN

// Parses the value of the active mruby exception
// NOTE SHOULD NOT BE CALLED IF NO EXCEPTION
std::string parse_ruby_exception(mrb_state *mrb)
{
    if (!mrb || !mrb->exc)
        return "No active Ruby exception";

    mrb_value exc = mrb_obj_value(mrb->exc);
    mrb_value msg = mrb_funcall(mrb, exc, "inspect", 0);

    if (mrb_string_p(msg)) {
        return std::string(mrb_str_to_cstr(mrb, msg));
    }

    return "Unparseable Ruby error";
}

NEXTPNR_NAMESPACE_END

#endif // NO_RUBY
