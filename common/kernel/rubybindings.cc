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

#ifndef NO_RUBY

#include "rubybindings.h"
#include "arch_rubybindings.h"
#include "json_frontend.h"
#include "log.h"
#include "nextpnr.h"

#include <fstream>
#include <memory>
#include <signal.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/compile.h>
#include <mruby/data.h>
#include <mruby/hash.h>
#include <mruby/string.h>
#include <mruby/value.h>
#include <mruby/variable.h>

NEXTPNR_NAMESPACE_BEGIN

static mrb_state *ruby_interp = nullptr;

mrb_state *get_ruby_state() { return ruby_interp; }

// Architecture-specific bindings (implemented per-arch)
void arch_wrap_ruby(mrb_state *mrb);

using namespace RubyConversion;

// -------------------------------------------------------
// PortRef string converter
// -------------------------------------------------------
namespace RubyConversion {
template <> struct string_converter<PortRef &>
{
    PortRef from_str(Context *ctx, const std::string &name)
    {
        NPNR_ASSERT_FALSE("PortRef from_str not implemented");
    }
    std::string to_str(Context *ctx, const PortRef &pr)
    {
        return pr.cell->name.str(ctx) + "." + pr.port.str(ctx);
    }
};

template <> struct string_converter<Property>
{
    Property from_str(Context *ctx, const std::string &s) { return Property::from_string(s); }
    std::string to_str(Context *ctx, Property p) { return p.to_string(); }
};
} // namespace RubyConversion

// -------------------------------------------------------
// Helper: load JSON into design
// -------------------------------------------------------
static void parse_json_shim(const std::string &filename, Context &d)
{
    std::ifstream inf(filename);
    if (!inf)
        throw std::runtime_error("failed to open file " + filename);
    parse_json(inf, filename, &d);
}

// -------------------------------------------------------
// mruby class storage (populated during init)
// -------------------------------------------------------
static struct RClass *rb_cContext = nullptr;
static struct RClass *rb_cCellInfo = nullptr;
static struct RClass *rb_cNetInfo = nullptr;
static struct RClass *rb_cPortInfo = nullptr;
static struct RClass *rb_cPortRef = nullptr;
static struct RClass *rb_cPipMap = nullptr;
static struct RClass *rb_cRegion = nullptr;
static struct RClass *rb_cHierarchicalCell = nullptr;
static struct RClass *rb_cLoc = nullptr;
static struct RClass *rb_cDelayPair = nullptr;
static struct RClass *rb_cDelayQuad = nullptr;
static struct RClass *rb_cGraphicElement = nullptr;
static struct RClass *rb_cClockFmax = nullptr;
static struct RClass *rb_cTimingResult = nullptr;

// -------------------------------------------------------
// Data types for mruby wrapping (C++ does not own these)
// -------------------------------------------------------
struct CtxWrap { Context *ctx; };
struct CellWrap { Context *ctx; CellInfo *ptr; };
struct NetWrap { Context *ctx; NetInfo *ptr; };
struct PortInfoWrap { Context *ctx; PortInfo *ptr; };
struct PortRefWrap { Context *ctx; PortRef pr; };
struct PipMapWrap { Context *ctx; PipMap *ptr; };
struct RegionWrap { Context *ctx; Region *ptr; };
struct HierWrap { Context *ctx; HierarchicalCell *ptr; };
struct LocWrap { int x, y, z; };
struct DelayPairWrap { DelayPair dp; };
struct DelayQuadWrap { DelayQuad dq; };
struct ClockFmaxWrap { ClockFmax cf; };
struct TimingResultWrap { Context *ctx; TimingResult *ptr; };

// Data type descriptors
static void wrap_free(mrb_state *, void *p) { delete static_cast<char*>(p); }
#define DEF_DATA_TYPE(name, type) \
    static const mrb_data_type name = { #type, [](mrb_state*, void* p) { delete static_cast<type*>(p); } }

DEF_DATA_TYPE(ctx_dt, CtxWrap);
DEF_DATA_TYPE(cell_dt, CellWrap);
DEF_DATA_TYPE(net_dt, NetWrap);
DEF_DATA_TYPE(portinfo_dt, PortInfoWrap);
DEF_DATA_TYPE(portref_dt, PortRefWrap);
DEF_DATA_TYPE(pipmap_dt, PipMapWrap);
DEF_DATA_TYPE(region_dt, RegionWrap);
DEF_DATA_TYPE(hier_dt, HierWrap);
DEF_DATA_TYPE(loc_dt, LocWrap);
DEF_DATA_TYPE(delaypair_dt, DelayPairWrap);
DEF_DATA_TYPE(delayquad_dt, DelayQuadWrap);
DEF_DATA_TYPE(clockfmax_dt, ClockFmaxWrap);
DEF_DATA_TYPE(timingresult_dt, TimingResultWrap);

// -------------------------------------------------------
// Map wrapper data types
// -------------------------------------------------------
typedef dict<IdString, Property> AttrMap;
typedef dict<IdString, PortInfo> PortMap;
typedef dict<IdString, IdString> IdIdMap;
typedef dict<IdString, std::unique_ptr<Region>> RegionMap;
typedef dict<WireId, PipMap> WireMap;
typedef indexed_store<PortRef> PortRefVector;
typedef dict<IdString, ClockFmax> ClockFmaxMap;

struct MapWrapBase { Context *ctx; void *ptr; };
static const mrb_data_type mapwrap_dt = { "MapWrap", [](mrb_state*, void* p) { delete static_cast<MapWrapBase*>(p); } };

// -------------------------------------------------------
// Helper: make a map-like Ruby object
// -------------------------------------------------------
template<typename MapType>
static mrb_value make_map_obj(mrb_state *mrb, struct RClass *cls, Context *ctx, MapType *map_ptr)
{
    auto *w = new MapWrapBase{ctx, static_cast<void*>(map_ptr)};
    return mrb_obj_value(mrb_data_object_alloc(mrb, cls, w, &mapwrap_dt));
}

// -------------------------------------------------------
// Loc class
// -------------------------------------------------------
static mrb_value loc_init(mrb_state *mrb, mrb_value self)
{
    mrb_int x, y, z;
    mrb_get_args(mrb, "iii", &x, &y, &z);
    auto *w = new LocWrap{(int)x, (int)y, (int)z};
    DATA_TYPE(self) = &loc_dt;
    DATA_PTR(self) = w;
    return self;
}
static mrb_value loc_x(mrb_state *mrb, mrb_value self) { return mrb_fixnum_value(((LocWrap*)DATA_PTR(self))->x); }
static mrb_value loc_y(mrb_state *mrb, mrb_value self) { return mrb_fixnum_value(((LocWrap*)DATA_PTR(self))->y); }
static mrb_value loc_z(mrb_state *mrb, mrb_value self) { return mrb_fixnum_value(((LocWrap*)DATA_PTR(self))->z); }
static mrb_value loc_inspect(mrb_state *mrb, mrb_value self)
{
    auto *w = (LocWrap*)DATA_PTR(self);
    char buf[64];
    snprintf(buf, sizeof(buf), "Loc(%d, %d, %d)", w->x, w->y, w->z);
    return mrb_str_new_cstr(mrb, buf);
}

// -------------------------------------------------------
// CellInfo bindings
// -------------------------------------------------------
static mrb_value cell_name(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->name.str(w->ctx).c_str());
}
static mrb_value cell_type(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->type.str(w->ctx).c_str());
}
static mrb_value cell_bel(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    if (w->ptr->bel == BelId())
        return mrb_nil_value();
    return mrb_str_new_cstr(mrb, w->ctx->getBelName(w->ptr->bel).str(w->ctx).c_str());
}
static mrb_value cell_addInput(mrb_state *mrb, mrb_value self)
{
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->addInput(w->ctx->id(name));
    return mrb_nil_value();
}
static mrb_value cell_addOutput(mrb_state *mrb, mrb_value self)
{
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->addOutput(w->ctx->id(name));
    return mrb_nil_value();
}
static mrb_value cell_addInout(mrb_state *mrb, mrb_value self)
{
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->addInout(w->ctx->id(name));
    return mrb_nil_value();
}
static mrb_value cell_setParam(mrb_state *mrb, mrb_value self)
{
    const char *name, *val; mrb_get_args(mrb, "zz", &name, &val);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->setParam(w->ctx->id(name), Property::from_string(val));
    return mrb_nil_value();
}
static mrb_value cell_unsetParam(mrb_state *mrb, mrb_value self)
{
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->unsetParam(w->ctx->id(name));
    return mrb_nil_value();
}
static mrb_value cell_setAttr(mrb_state *mrb, mrb_value self)
{
    const char *name, *val; mrb_get_args(mrb, "zz", &name, &val);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->setAttr(w->ctx->id(name), Property::from_string(val));
    return mrb_nil_value();
}
static mrb_value cell_unsetAttr(mrb_state *mrb, mrb_value self)
{
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CellWrap*)DATA_PTR(self);
    w->ptr->unsetAttr(w->ctx->id(name));
    return mrb_nil_value();
}

// CellInfo attrs/params/ports: return map-like objects
static struct RClass *rb_cAttrMap = nullptr;
static struct RClass *rb_cPortMap = nullptr;
static struct RClass *rb_cIdIdMap = nullptr;
static struct RClass *rb_cWireMap = nullptr;
static struct RClass *rb_cRegionMap = nullptr;
static struct RClass *rb_cPortRefVector = nullptr;
static struct RClass *rb_cClockFmaxMap = nullptr;

// AttrMap methods (dict<IdString, Property>)
static mrb_value attrmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<AttrMap*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        mrb_value val = mrb_str_new_cstr(mrb, kv.second.to_string().c_str());
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value attrmap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<AttrMap*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    return mrb_str_new_cstr(mrb, it->second.to_string().c_str());
}
static mrb_value attrmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<AttrMap*>(w->ptr)->size());
}

// PortMap methods (dict<IdString, PortInfo>)
static mrb_value portmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<PortMap*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        auto *pw = new PortInfoWrap{w->ctx, &kv.second};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cPortInfo, pw, &portinfo_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value portmap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<PortMap*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    auto *pw = new PortInfoWrap{w->ctx, &it->second};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cPortInfo, pw, &portinfo_dt));
}
static mrb_value portmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<PortMap*>(w->ptr)->size());
}

// WireMap methods (dict<WireId, PipMap>)
static mrb_value wiremap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<WireMap*>(w->ptr);
    for (auto &kv : *map) {
        std::string key_str;
        if (kv.first != WireId())
            key_str = w->ctx->getWireName(kv.first).str(w->ctx);
        mrb_value key = mrb_str_new_cstr(mrb, key_str.c_str());
        auto *pm = new PipMapWrap{w->ctx, &kv.second};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cPipMap, pm, &pipmap_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value wiremap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<WireMap*>(w->ptr)->size());
}

// cell_attrs / cell_params / cell_ports
static mrb_value cell_attrs(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cAttrMap, w->ctx, &w->ptr->attrs);
}
static mrb_value cell_params(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cAttrMap, w->ctx, &w->ptr->params);
}
static mrb_value cell_ports(mrb_state *mrb, mrb_value self)
{
    auto *w = (CellWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cPortMap, w->ctx, &w->ptr->ports);
}

// -------------------------------------------------------
// PortInfo bindings
// -------------------------------------------------------
static mrb_value portinfo_name(mrb_state *mrb, mrb_value self)
{
    auto *w = (PortInfoWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->name.str(w->ctx).c_str());
}
static mrb_value portinfo_net(mrb_state *mrb, mrb_value self)
{
    auto *w = (PortInfoWrap*)DATA_PTR(self);
    if (w->ptr->net == nullptr) return mrb_nil_value();
    auto *nw = new NetWrap{w->ctx, w->ptr->net};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cNetInfo, nw, &net_dt));
}
static mrb_value portinfo_type(mrb_state *mrb, mrb_value self)
{
    auto *w = (PortInfoWrap*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)w->ptr->type);
}

// -------------------------------------------------------
// NetInfo bindings
// -------------------------------------------------------
static mrb_value net_name(mrb_state *mrb, mrb_value self)
{
    auto *w = (NetWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->name.str(w->ctx).c_str());
}
static mrb_value net_driver(mrb_state *mrb, mrb_value self)
{
    auto *w = (NetWrap*)DATA_PTR(self);
    auto *prw = new PortRefWrap{w->ctx, w->ptr->driver};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cPortRef, prw, &portref_dt));
}
static mrb_value net_users(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&!", &block);
    auto *w = (NetWrap*)DATA_PTR(self);
    for (auto &user : w->ptr->users) {
        auto *prw = new PortRefWrap{w->ctx, *user};
        mrb_value u = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cPortRef, prw, &portref_dt));
        mrb_yield(mrb, block, u);
    }
    return self;
}
static mrb_value net_users_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (NetWrap*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)w->ptr->users.capacity());
}
static mrb_value net_wires(mrb_state *mrb, mrb_value self)
{
    auto *w = (NetWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cWireMap, w->ctx, &w->ptr->wires);
}
static mrb_value net_attrs(mrb_state *mrb, mrb_value self)
{
    auto *w = (NetWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cAttrMap, w->ctx, &w->ptr->attrs);
}

// -------------------------------------------------------
// PortRef bindings
// -------------------------------------------------------
static mrb_value portref_cell(mrb_state *mrb, mrb_value self)
{
    auto *w = (PortRefWrap*)DATA_PTR(self);
    if (w->pr.cell == nullptr) return mrb_nil_value();
    auto *cw = new CellWrap{w->ctx, w->pr.cell};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cCellInfo, cw, &cell_dt));
}
static mrb_value portref_port(mrb_state *mrb, mrb_value self)
{
    auto *w = (PortRefWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->pr.port.str(w->ctx).c_str());
}

// -------------------------------------------------------
// PipMap bindings
// -------------------------------------------------------
static mrb_value pipmap_pip(mrb_state *mrb, mrb_value self)
{
    auto *w = (PipMapWrap*)DATA_PTR(self);
    if (w->ptr->pip == PipId()) return mrb_nil_value();
    return mrb_str_new_cstr(mrb, w->ctx->getPipName(w->ptr->pip).str(w->ctx).c_str());
}
static mrb_value pipmap_strength(mrb_state *mrb, mrb_value self)
{
    auto *w = (PipMapWrap*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)w->ptr->strength);
}

// -------------------------------------------------------
// Region bindings
// -------------------------------------------------------
static mrb_value region_name(mrb_state *mrb, mrb_value self)
{
    auto *w = (RegionWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->name.str(w->ctx).c_str());
}

// -------------------------------------------------------
// HierarchicalCell bindings
// -------------------------------------------------------
static mrb_value hier_name(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->name.str(w->ctx).c_str());
}
static mrb_value hier_type(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->type.str(w->ctx).c_str());
}
static mrb_value hier_parent(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->parent.str(w->ctx).c_str());
}
static mrb_value hier_fullpath(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ptr->fullpath.str(w->ctx).c_str());
}
static mrb_value hier_leaf_cells(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cIdIdMap, w->ctx, &w->ptr->leaf_cells);
}
static mrb_value hier_nets(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cIdIdMap, w->ctx, &w->ptr->nets);
}
static mrb_value hier_hier_cells(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cIdIdMap, w->ctx, &w->ptr->hier_cells);
}
static mrb_value hier_attrs(mrb_state *mrb, mrb_value self)
{
    auto *w = (HierWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cAttrMap, w->ctx, &w->ptr->attrs);
}

// -------------------------------------------------------
// DelayPair bindings
// -------------------------------------------------------
static mrb_value delaypair_min(mrb_state *mrb, mrb_value self)
{
    auto *w = (DelayPairWrap*)DATA_PTR(self);
    return mrb_fixnum_value(w->dp.minDelay());
}
static mrb_value delaypair_max(mrb_state *mrb, mrb_value self)
{
    auto *w = (DelayPairWrap*)DATA_PTR(self);
    return mrb_fixnum_value(w->dp.maxDelay());
}

// -------------------------------------------------------
// ClockFmax bindings
// -------------------------------------------------------
static mrb_value clockfmax_achieved(mrb_state *mrb, mrb_value self)
{
    auto *w = (ClockFmaxWrap*)DATA_PTR(self);
    return mrb_float_value(mrb, w->cf.achieved);
}
static mrb_value clockfmax_constraint(mrb_state *mrb, mrb_value self)
{
    auto *w = (ClockFmaxWrap*)DATA_PTR(self);
    return mrb_float_value(mrb, w->cf.constraint);
}

// -------------------------------------------------------
// TimingResult bindings
// -------------------------------------------------------
static mrb_value timingresult_clock_fmax(mrb_state *mrb, mrb_value self)
{
    auto *w = (TimingResultWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cClockFmaxMap, w->ctx, &w->ptr->clock_fmax);
}

// -------------------------------------------------------
// IdIdMap methods (dict<IdString, IdString>)
// -------------------------------------------------------
static mrb_value ididmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<IdIdMap*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        mrb_value val = mrb_str_new_cstr(mrb, kv.second.str(w->ctx).c_str());
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value ididmap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<IdIdMap*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    return mrb_str_new_cstr(mrb, it->second.str(w->ctx).c_str());
}
static mrb_value ididmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<IdIdMap*>(w->ptr)->size());
}

// ClockFmaxMap methods
static mrb_value clockfmaxmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<ClockFmaxMap*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        auto *cfw = new ClockFmaxWrap{kv.second};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cClockFmax, cfw, &clockfmax_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value clockfmaxmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<ClockFmaxMap*>(w->ptr)->size());
}

// -------------------------------------------------------
// Specialization: wrap_object for Context
// -------------------------------------------------------
namespace RubyConversion {
template <> mrb_value wrap_object<Context>(mrb_state *mrb, Context &ctx)
{
    auto *w = new CtxWrap{&ctx};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cContext, w, &ctx_dt));
}
} // namespace RubyConversion

// -------------------------------------------------------
// Register all classes and methods
// -------------------------------------------------------
static void register_nextpnr_types(mrb_state *mrb)
{
    // Loc
    rb_cLoc = mrb_define_class(mrb, "Loc", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cLoc, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cLoc, "initialize", loc_init, MRB_ARGS_REQ(3));
    mrb_define_method(mrb, rb_cLoc, "x", loc_x, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cLoc, "y", loc_y, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cLoc, "z", loc_z, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cLoc, "inspect", loc_inspect, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cLoc, "to_s", loc_inspect, MRB_ARGS_NONE());

    // CellInfo
    rb_cCellInfo = mrb_define_class(mrb, "CellInfo", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cCellInfo, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cCellInfo, "name", cell_name, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "type", cell_type, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "bel", cell_bel, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "attrs", cell_attrs, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "params", cell_params, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "ports", cell_ports, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellInfo, "addInput", cell_addInput, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cCellInfo, "addOutput", cell_addOutput, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cCellInfo, "addInout", cell_addInout, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cCellInfo, "setParam", cell_setParam, MRB_ARGS_REQ(2));
    mrb_define_method(mrb, rb_cCellInfo, "unsetParam", cell_unsetParam, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cCellInfo, "setAttr", cell_setAttr, MRB_ARGS_REQ(2));
    mrb_define_method(mrb, rb_cCellInfo, "unsetAttr", cell_unsetAttr, MRB_ARGS_REQ(1));

    // PortInfo
    rb_cPortInfo = mrb_define_class(mrb, "PortInfo", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cPortInfo, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cPortInfo, "name", portinfo_name, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cPortInfo, "net", portinfo_net, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cPortInfo, "type", portinfo_type, MRB_ARGS_NONE());

    // NetInfo
    rb_cNetInfo = mrb_define_class(mrb, "NetInfo", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cNetInfo, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cNetInfo, "name", net_name, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cNetInfo, "driver", net_driver, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cNetInfo, "each_user", net_users, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cNetInfo, "users_length", net_users_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cNetInfo, "wires", net_wires, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cNetInfo, "attrs", net_attrs, MRB_ARGS_NONE());

    // PortRef
    rb_cPortRef = mrb_define_class(mrb, "PortRef", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cPortRef, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cPortRef, "cell", portref_cell, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cPortRef, "port", portref_port, MRB_ARGS_NONE());

    // PipMap
    rb_cPipMap = mrb_define_class(mrb, "PipMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cPipMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cPipMap, "pip", pipmap_pip, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cPipMap, "strength", pipmap_strength, MRB_ARGS_NONE());

    // Region
    rb_cRegion = mrb_define_class(mrb, "Region", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cRegion, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cRegion, "name", region_name, MRB_ARGS_NONE());

    // HierarchicalCell
    rb_cHierarchicalCell = mrb_define_class(mrb, "HierarchicalCell", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cHierarchicalCell, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cHierarchicalCell, "name", hier_name, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "type", hier_type, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "parent", hier_parent, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "fullpath", hier_fullpath, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "leaf_cells", hier_leaf_cells, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "nets", hier_nets, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "hier_cells", hier_hier_cells, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchicalCell, "attrs", hier_attrs, MRB_ARGS_NONE());

    // DelayPair
    rb_cDelayPair = mrb_define_class(mrb, "DelayPair", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cDelayPair, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cDelayPair, "minDelay", delaypair_min, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cDelayPair, "maxDelay", delaypair_max, MRB_ARGS_NONE());

    // ClockFmax
    rb_cClockFmax = mrb_define_class(mrb, "ClockFmax", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cClockFmax, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cClockFmax, "achieved", clockfmax_achieved, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cClockFmax, "constraint", clockfmax_constraint, MRB_ARGS_NONE());

    // TimingResult
    rb_cTimingResult = mrb_define_class(mrb, "TimingResult", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cTimingResult, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cTimingResult, "clock_fmax", timingresult_clock_fmax, MRB_ARGS_NONE());

    // Map classes
    rb_cAttrMap = mrb_define_class(mrb, "AttrMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cAttrMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cAttrMap, "each", attrmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cAttrMap, "[]", attrmap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cAttrMap, "length", attrmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cAttrMap, "size", attrmap_length, MRB_ARGS_NONE());

    rb_cPortMap = mrb_define_class(mrb, "PortMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cPortMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cPortMap, "each", portmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cPortMap, "[]", portmap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cPortMap, "length", portmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cPortMap, "size", portmap_length, MRB_ARGS_NONE());

    rb_cIdIdMap = mrb_define_class(mrb, "IdIdMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cIdIdMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cIdIdMap, "each", ididmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cIdIdMap, "[]", ididmap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cIdIdMap, "length", ididmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cIdIdMap, "size", ididmap_length, MRB_ARGS_NONE());

    rb_cWireMap = mrb_define_class(mrb, "WireMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cWireMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cWireMap, "each", wiremap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cWireMap, "length", wiremap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cWireMap, "size", wiremap_length, MRB_ARGS_NONE());

    rb_cClockFmaxMap = mrb_define_class(mrb, "ClockFmaxMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cClockFmaxMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cClockFmaxMap, "each", clockfmaxmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cClockFmaxMap, "length", clockfmaxmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cClockFmaxMap, "size", clockfmaxmap_length, MRB_ARGS_NONE());

    // Enum constants
    mrb_define_const(mrb, mrb->object_class, "PORT_IN", mrb_fixnum_value(PORT_IN));
    mrb_define_const(mrb, mrb->object_class, "PORT_OUT", mrb_fixnum_value(PORT_OUT));
    mrb_define_const(mrb, mrb->object_class, "PORT_INOUT", mrb_fixnum_value(PORT_INOUT));

    mrb_define_const(mrb, mrb->object_class, "STRENGTH_NONE", mrb_fixnum_value(STRENGTH_NONE));
    mrb_define_const(mrb, mrb->object_class, "STRENGTH_WEAK", mrb_fixnum_value(STRENGTH_WEAK));
    mrb_define_const(mrb, mrb->object_class, "STRENGTH_STRONG", mrb_fixnum_value(STRENGTH_STRONG));
    mrb_define_const(mrb, mrb->object_class, "STRENGTH_FIXED", mrb_fixnum_value(STRENGTH_FIXED));
    mrb_define_const(mrb, mrb->object_class, "STRENGTH_LOCKED", mrb_fixnum_value(STRENGTH_LOCKED));
    mrb_define_const(mrb, mrb->object_class, "STRENGTH_USER", mrb_fixnum_value(STRENGTH_USER));

    // Register architecture-specific types
    arch_wrap_ruby(mrb);
}

// -------------------------------------------------------
// Lifecycle functions
// -------------------------------------------------------
void init_ruby(const char *executable)
{
    ruby_interp = mrb_open();
    if (!ruby_interp) {
        log_error("Failed to initialize mruby interpreter\n");
        return;
    }
    register_nextpnr_types(ruby_interp);
}

void deinit_ruby()
{
    if (ruby_interp) {
        mrb_close(ruby_interp);
        ruby_interp = nullptr;
    }
}

void execute_ruby_file(const char *ruby_file)
{
    if (!ruby_interp) {
        log_error("Ruby interpreter not initialized\n");
        return;
    }
    FILE *fp = fopen(ruby_file, "r");
    if (!fp) {
        fprintf(stderr, "Fatal error: file not found %s\n", ruby_file);
        exit(1);
    }
    mrbc_context *cxt = mrbc_context_new(ruby_interp);
    mrbc_filename(ruby_interp, cxt, ruby_file);
    mrb_load_file_cxt(ruby_interp, fp, cxt);
    mrbc_context_free(ruby_interp, cxt);
    fclose(fp);

    if (ruby_interp->exc) {
        mrb_value exc = mrb_obj_value(ruby_interp->exc);
        mrb_value msg = mrb_funcall(ruby_interp, exc, "inspect", 0);
        const char *err_str = mrb_str_to_cstr(ruby_interp, msg);
        ruby_interp->exc = 0;
        log_error("Error in Ruby script %s: %s\n", ruby_file, err_str);
    }
}

NEXTPNR_NAMESPACE_END

#endif // NO_RUBY
