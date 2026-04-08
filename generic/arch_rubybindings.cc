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

#include "arch_rubybindings.h"
#include "nextpnr.h"
#include "rubybindings.h"

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/string.h>
#include <mruby/value.h>

NEXTPNR_NAMESPACE_BEGIN

// Forward declarations from rubybindings.cc
struct CtxWrap;
struct CellWrap;
struct NetWrap;
struct HierWrap;
struct TimingResultWrap;
extern const mrb_data_type ctx_dt;
extern const mrb_data_type cell_dt;
extern const mrb_data_type net_dt;
extern const mrb_data_type hier_dt;
extern const mrb_data_type timingresult_dt;
extern const mrb_data_type mapwrap_dt;
struct MapWrapBase;
template<typename T> mrb_value make_map_obj(mrb_state*, struct RClass*, Context*, T*);

extern struct RClass *rb_cCellInfo;
extern struct RClass *rb_cNetInfo;
extern struct RClass *rb_cPortInfo;
extern struct RClass *rb_cPortRef;
extern struct RClass *rb_cPipMap;
extern struct RClass *rb_cRegion;
extern struct RClass *rb_cHierarchicalCell;
extern struct RClass *rb_cLoc;
extern struct RClass *rb_cTimingResult;
extern struct RClass *rb_cAttrMap;
extern struct RClass *rb_cIdIdMap;
extern struct RClass *rb_cWireMap;
extern struct RClass *rb_cClockFmaxMap;

extern const mrb_data_type loc_dt;
struct LocWrap;

// Map classes for this architecture
static struct RClass *rb_cCellMap = nullptr;
static struct RClass *rb_cNetMap = nullptr;
static struct RClass *rb_cHierarchyMap = nullptr;

// CellMap (dict<IdString, unique_ptr<CellInfo>>) - each yields [name, CellInfo]
static mrb_value cellmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, std::unique_ptr<CellInfo>>*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        auto *cw = new CellWrap{w->ctx, kv.second.get()};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cCellInfo, cw, &cell_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value cellmap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, std::unique_ptr<CellInfo>>*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    auto *cw = new CellWrap{w->ctx, it->second.get()};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cCellInfo, cw, &cell_dt));
}
static mrb_value cellmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<dict<IdString, std::unique_ptr<CellInfo>>*>(w->ptr)->size());
}

// NetMap (dict<IdString, unique_ptr<NetInfo>>)
static mrb_value netmap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, std::unique_ptr<NetInfo>>*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        auto *nw = new NetWrap{w->ctx, kv.second.get()};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cNetInfo, nw, &net_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value netmap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, std::unique_ptr<NetInfo>>*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    auto *nw = new NetWrap{w->ctx, it->second.get()};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cNetInfo, nw, &net_dt));
}
static mrb_value netmap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<dict<IdString, std::unique_ptr<NetInfo>>*>(w->ptr)->size());
}

// HierarchyMap (dict<IdString, HierarchicalCell>)
static mrb_value hiermap_each(mrb_state *mrb, mrb_value self)
{
    mrb_value block; mrb_get_args(mrb, "&", &block);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, HierarchicalCell>*>(w->ptr);
    for (auto &kv : *map) {
        mrb_value key = mrb_str_new_cstr(mrb, kv.first.str(w->ctx).c_str());
        auto *hw = new HierWrap{w->ctx, &kv.second};
        mrb_value val = mrb_obj_value(mrb_data_object_alloc(mrb, rb_cHierarchicalCell, hw, &hier_dt));
        mrb_value pair[2] = {key, val};
        mrb_yield(mrb, block, mrb_ary_new_from_values(mrb, 2, pair));
    }
    return self;
}
static mrb_value hiermap_getitem(mrb_state *mrb, mrb_value self)
{
    const char *key; mrb_get_args(mrb, "z", &key);
    auto *w = (MapWrapBase*)DATA_PTR(self);
    auto *map = static_cast<dict<IdString, HierarchicalCell>*>(w->ptr);
    IdString k = w->ctx->id(key);
    auto it = map->find(k);
    if (it == map->end()) return mrb_nil_value();
    auto *hw = new HierWrap{w->ctx, &it->second};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cHierarchicalCell, hw, &hier_dt));
}
static mrb_value hiermap_length(mrb_state *mrb, mrb_value self)
{
    auto *w = (MapWrapBase*)DATA_PTR(self);
    return mrb_fixnum_value((mrb_int)static_cast<dict<IdString, HierarchicalCell>*>(w->ptr)->size());
}

void arch_wrap_ruby(mrb_state *mrb)
{
    // Register CellMap, NetMap, HierarchyMap
    rb_cCellMap = mrb_define_class(mrb, "CellMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cCellMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cCellMap, "each", cellmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cCellMap, "[]", cellmap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cCellMap, "length", cellmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cCellMap, "size", cellmap_length, MRB_ARGS_NONE());

    rb_cNetMap = mrb_define_class(mrb, "NetMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cNetMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cNetMap, "each", netmap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cNetMap, "[]", netmap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cNetMap, "length", netmap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cNetMap, "size", netmap_length, MRB_ARGS_NONE());

    rb_cHierarchyMap = mrb_define_class(mrb, "HierarchyMap", mrb->object_class);
    MRB_SET_INSTANCE_TT(rb_cHierarchyMap, MRB_TT_DATA);
    mrb_define_method(mrb, rb_cHierarchyMap, "each", hiermap_each, MRB_ARGS_BLOCK());
    mrb_define_method(mrb, rb_cHierarchyMap, "[]", hiermap_getitem, MRB_ARGS_REQ(1));
    mrb_define_method(mrb, rb_cHierarchyMap, "length", hiermap_length, MRB_ARGS_NONE());
    mrb_define_method(mrb, rb_cHierarchyMap, "size", hiermap_length, MRB_ARGS_NONE());

    // Context class with arch-shared bindings
    auto *ctx_cls = mrb_define_class(mrb, "Context", mrb->object_class);
    MRB_SET_INSTANCE_TT(ctx_cls, MRB_TT_DATA);

    // Include shared bindings (cells, nets, pack, place, route, etc.)
#include "arch_rubybindings_shared.h"

    // Generic arch-specific: addWire, addPip, addBel, timing, etc.
    mrb_define_method(mrb, ctx_cls, "addWire", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *name, *type; mrb_int x, y;
        mrb_get_args(mrb, "zzii", &name, &type, &x, &y);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addWire(IdStringList::parse(w->ctx, name), w->ctx->id(type), (int)x, (int)y);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(4));

    mrb_define_method(mrb, ctx_cls, "addPip", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *name, *type, *srcWire, *dstWire;
        mrb_int delay; mrb_value loc_v;
        mrb_get_args(mrb, "zzzzio", &name, &type, &srcWire, &dstWire, &delay, &loc_v);
        auto *w = (CtxWrap*)DATA_PTR(self);
        auto *lw = (LocWrap*)DATA_PTR(loc_v);
        Loc loc; loc.x = lw->x; loc.y = lw->y; loc.z = lw->z;
        w->ctx->addPip(IdStringList::parse(w->ctx, name), w->ctx->id(type),
                       w->ctx->getWireByNameStr(srcWire), w->ctx->getWireByNameStr(dstWire),
                       (delay_t)delay, loc);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(6));

    mrb_define_method(mrb, ctx_cls, "addBel", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *name, *type; mrb_value loc_v; mrb_bool gb, hidden;
        mrb_get_args(mrb, "zzobb", &name, &type, &loc_v, &gb, &hidden);
        auto *w = (CtxWrap*)DATA_PTR(self);
        auto *lw = (LocWrap*)DATA_PTR(loc_v);
        Loc loc; loc.x = lw->x; loc.y = lw->y; loc.z = lw->z;
        w->ctx->addBel(IdStringList::parse(w->ctx, name), w->ctx->id(type), loc, (bool)gb, (bool)hidden);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(5));

    mrb_define_method(mrb, ctx_cls, "addBelInput", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *bel, *name, *wire;
        mrb_get_args(mrb, "zzz", &bel, &name, &wire);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addBelInput(w->ctx->getBelByNameStr(bel), w->ctx->id(name), w->ctx->getWireByNameStr(wire));
        return mrb_nil_value();
    }, MRB_ARGS_REQ(3));

    mrb_define_method(mrb, ctx_cls, "addBelOutput", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *bel, *name, *wire;
        mrb_get_args(mrb, "zzz", &bel, &name, &wire);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addBelOutput(w->ctx->getBelByNameStr(bel), w->ctx->id(name), w->ctx->getWireByNameStr(wire));
        return mrb_nil_value();
    }, MRB_ARGS_REQ(3));

    mrb_define_method(mrb, ctx_cls, "addBelInout", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *bel, *name, *wire;
        mrb_get_args(mrb, "zzz", &bel, &name, &wire);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addBelInout(w->ctx->getBelByNameStr(bel), w->ctx->id(name), w->ctx->getWireByNameStr(wire));
        return mrb_nil_value();
    }, MRB_ARGS_REQ(3));

    // Timing
    mrb_define_method(mrb, ctx_cls, "addCellTimingClock", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *cell, *port;
        mrb_get_args(mrb, "zz", &cell, &port);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addCellTimingClock(w->ctx->id(cell), w->ctx->id(port));
        return mrb_nil_value();
    }, MRB_ARGS_REQ(2));

    mrb_define_method(mrb, ctx_cls, "addCellTimingDelay", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *cell, *fromPort, *toPort; mrb_int delay;
        mrb_get_args(mrb, "zzzi", &cell, &fromPort, &toPort, &delay);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addCellTimingDelay(w->ctx->id(cell), w->ctx->id(fromPort), w->ctx->id(toPort), (delay_t)delay);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(4));

    mrb_define_method(mrb, ctx_cls, "addCellTimingSetupHold", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *cell, *port, *clock; mrb_int setup, hold;
        mrb_get_args(mrb, "zzzii", &cell, &port, &clock, &setup, &hold);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addCellTimingSetupHold(w->ctx->id(cell), w->ctx->id(port), w->ctx->id(clock),
                                       (delay_t)setup, (delay_t)hold);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(5));

    mrb_define_method(mrb, ctx_cls, "addCellTimingClockToOut", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        const char *cell, *port, *clock; mrb_int clktoq;
        mrb_get_args(mrb, "zzzi", &cell, &port, &clock, &clktoq);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->addCellTimingClockToOut(w->ctx->id(cell), w->ctx->id(port), w->ctx->id(clock), (delay_t)clktoq);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(4));

    mrb_define_method(mrb, ctx_cls, "setLutK", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        mrb_int k; mrb_get_args(mrb, "i", &k);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->setLutK((int)k);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(1));

    mrb_define_method(mrb, ctx_cls, "setDelayScaling", [](mrb_state *mrb, mrb_value self) -> mrb_value {
        mrb_float scale, offset;
        mrb_get_args(mrb, "ff", &scale, &offset);
        auto *w = (CtxWrap*)DATA_PTR(self);
        w->ctx->setDelayScaling((double)scale, (double)offset);
        return mrb_nil_value();
    }, MRB_ARGS_REQ(2));
}

NEXTPNR_NAMESPACE_END

#endif // NO_RUBY
