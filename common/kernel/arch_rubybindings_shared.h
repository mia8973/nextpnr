// Common Ruby bindings #included by all arches
// This file is included inside arch_wrap_ruby() after ctx_cls is defined.
// It registers Context methods using the mruby C API.

// --- Context property accessors ---

// ctx.cells -> CellMap (each yields [name_str, CellInfo])
mrb_define_method(mrb, ctx_cls, "cells", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cCellMap, w->ctx, &w->ctx->cells);
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "nets", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cNetMap, w->ctx, &w->ctx->nets);
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "hierarchy", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return make_map_obj(mrb, rb_cHierarchyMap, w->ctx, &w->ctx->hierarchy);
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "top_module", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ctx->top_module.str(w->ctx).c_str());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "timing_result", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    auto *tw = new TimingResultWrap{w->ctx, &w->ctx->timing_result};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cTimingResult, tw, &timingresult_dt));
}, MRB_ARGS_NONE());

// --- Flow control ---

mrb_define_method(mrb, ctx_cls, "checksum", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_fixnum_value(w->ctx->checksum());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "pack", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->pack());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "place", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->place());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "route", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->route());
}, MRB_ARGS_NONE());

// --- Netlist manipulation ---

mrb_define_method(mrb, ctx_cls, "createNet", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *name; mrb_get_args(mrb, "z", &name);
    auto *w = (CtxWrap*)DATA_PTR(self);
    NetInfo *ni = w->ctx->createNet(w->ctx->id(name));
    if (!ni) return mrb_nil_value();
    auto *nw = new NetWrap{w->ctx, ni};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cNetInfo, nw, &net_dt));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "createCell", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *name, *type; mrb_get_args(mrb, "zz", &name, &type);
    auto *w = (CtxWrap*)DATA_PTR(self);
    CellInfo *ci = w->ctx->createCell(w->ctx->id(name), w->ctx->id(type));
    if (!ci) return mrb_nil_value();
    auto *cw = new CellWrap{w->ctx, ci};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cCellInfo, cw, &cell_dt));
}, MRB_ARGS_REQ(2));

mrb_define_method(mrb, ctx_cls, "connectPort", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *net, *cell, *port; mrb_get_args(mrb, "zzz", &net, &cell, &port);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->connectPort(w->ctx->id(net), w->ctx->id(cell), w->ctx->id(port));
    return mrb_nil_value();
}, MRB_ARGS_REQ(3));

mrb_define_method(mrb, ctx_cls, "disconnectPort", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *cell, *port; mrb_get_args(mrb, "zz", &cell, &port);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->disconnectPort(w->ctx->id(cell), w->ctx->id(port));
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

mrb_define_method(mrb, ctx_cls, "ripupNet", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *net; mrb_get_args(mrb, "z", &net);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->ripupNet(w->ctx->id(net));
    return mrb_nil_value();
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "lockNetRouting", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *net; mrb_get_args(mrb, "z", &net);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->lockNetRouting(w->ctx->id(net));
    return mrb_nil_value();
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "copyBelPorts", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *cell, *bel; mrb_get_args(mrb, "zz", &cell, &bel);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->copyBelPorts(w->ctx->id(cell), w->ctx->getBelByNameStr(bel));
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

// --- Clock / constraints ---

mrb_define_method(mrb, ctx_cls, "addClock", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *net; mrb_float freq;
    mrb_get_args(mrb, "zf", &net, &freq);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->addClock(w->ctx->id(net), (float)freq);
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

mrb_define_method(mrb, ctx_cls, "createRectangularRegion", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *name; mrb_int x0, y0, x1, y1;
    mrb_get_args(mrb, "ziiii", &name, &x0, &y0, &x1, &y1);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->createRectangularRegion(w->ctx->id(name), (int)x0, (int)y0, (int)x1, (int)y1);
    return mrb_nil_value();
}, MRB_ARGS_REQ(5));

mrb_define_method(mrb, ctx_cls, "addBelToRegion", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *region, *bel; mrb_get_args(mrb, "zz", &region, &bel);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->addBelToRegion(w->ctx->id(region), w->ctx->getBelByNameStr(bel));
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

mrb_define_method(mrb, ctx_cls, "constrainCellToRegion", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *cell, *region; mrb_get_args(mrb, "zz", &cell, &region);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->constrainCellToRegion(w->ctx->id(cell), w->ctx->id(region));
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

// --- Architecture queries ---

mrb_define_method(mrb, ctx_cls, "getBelType", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *bel; mrb_get_args(mrb, "z", &bel);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ctx->getBelType(w->ctx->getBelByNameStr(bel)).str(w->ctx).c_str());
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "getBelLocation", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *bel; mrb_get_args(mrb, "z", &bel);
    auto *w = (CtxWrap*)DATA_PTR(self);
    Loc l = w->ctx->getBelLocation(w->ctx->getBelByNameStr(bel));
    auto *lw = new LocWrap{l.x, l.y, l.z};
    return mrb_obj_value(mrb_data_object_alloc(mrb, rb_cLoc, lw, &loc_dt));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "checkBelAvail", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *bel; mrb_get_args(mrb, "z", &bel);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->checkBelAvail(w->ctx->getBelByNameStr(bel)));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "checkWireAvail", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *wire; mrb_get_args(mrb, "z", &wire);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->checkWireAvail(w->ctx->getWireByNameStr(wire)));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "checkPipAvail", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *pip; mrb_get_args(mrb, "z", &pip);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_bool_value(w->ctx->checkPipAvail(w->ctx->getPipByNameStr(pip)));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "getPipSrcWire", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *pip; mrb_get_args(mrb, "z", &pip);
    auto *w = (CtxWrap*)DATA_PTR(self);
    WireId wire = w->ctx->getPipSrcWire(w->ctx->getPipByNameStr(pip));
    if (wire == WireId()) return mrb_nil_value();
    return mrb_str_new_cstr(mrb, w->ctx->getWireName(wire).str(w->ctx).c_str());
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "getPipDstWire", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *pip; mrb_get_args(mrb, "z", &pip);
    auto *w = (CtxWrap*)DATA_PTR(self);
    WireId wire = w->ctx->getPipDstWire(w->ctx->getPipByNameStr(pip));
    if (wire == WireId()) return mrb_nil_value();
    return mrb_str_new_cstr(mrb, w->ctx->getWireName(wire).str(w->ctx).c_str());
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "getChipName", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ctx->getChipName().c_str());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "archId", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_str_new_cstr(mrb, w->ctx->archId().str(w->ctx).c_str());
}, MRB_ARGS_NONE());

mrb_define_method(mrb, ctx_cls, "getDelayFromNS", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    mrb_float ns; mrb_get_args(mrb, "f", &ns);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_fixnum_value(w->ctx->getDelayFromNS((double)ns));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "getDelayNS", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    mrb_int delay; mrb_get_args(mrb, "i", &delay);
    auto *w = (CtxWrap*)DATA_PTR(self);
    return mrb_float_value(mrb, w->ctx->getDelayNS((delay_t)delay));
}, MRB_ARGS_REQ(1));

mrb_define_method(mrb, ctx_cls, "writeSVG", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    const char *file, *flags; mrb_get_args(mrb, "zz", &file, &flags);
    auto *w = (CtxWrap*)DATA_PTR(self);
    w->ctx->writeSVG(file, flags);
    return mrb_nil_value();
}, MRB_ARGS_REQ(2));

mrb_define_method(mrb, ctx_cls, "getNameDelimiter", [](mrb_state *mrb, mrb_value self) -> mrb_value {
    auto *w = (CtxWrap*)DATA_PTR(self);
    char buf[2] = {w->ctx->getNameDelimiter(), 0};
    return mrb_str_new_cstr(mrb, buf);
}, MRB_ARGS_NONE());
