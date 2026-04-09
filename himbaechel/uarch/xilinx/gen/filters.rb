# Mapping rules from prjxray to nextpnr

def get_bel_z_override(bel, default_z)
  s = bel.site
  t = s.tile
  bt = bel.bel_type
  bn = bel.name
  if t.tile_type == "BRAM_L" || t.tile_type == "BRAM_R"
    is_top18 = (s.primary.site_type == "RAMB18E1")
    return 0 if bt == "RAMBFIFO36E1_RAMBFIFO36E1"
    return 1 if bt == "RAMB36E1_RAMB36E1"
    return 2 if bt == "FIFO36E1_FIFO36E1"
    return (is_top18 ? 5 : 9) if bt == "RAMB18E1_RAMB18E1"
    return 10 if bt == "FIFO18E1_FIFO18E1"
  end
  if s.site_type == "SLICEL" || s.site_type == "SLICEM"
    is_upper_site = (s.rel_xy[0] == 1)
    subslices = "ABCD"
    postfixes = ["6LUT", "5LUT", "FF", "5FF"]
    postfixes.each_with_index do |pf, i|
      if bn.length == pf.length + 1 && bn[1..] == pf
        return (is_upper_site ? 64 : 0) | (subslices.index(bn[0]) << 4) | i
      end
    end
    if bn == "F7AMUX"
      return (is_upper_site ? 0x47 : 0x07)
    elsif bn == "F7BMUX"
      return (is_upper_site ? 0x67 : 0x27)
    elsif bn == "F8MUX"
      return (is_upper_site ? 0x48 : 0x08)
    elsif bn == "CARRY4"
      return (is_upper_site ? 0x4F : 0x0F)
    end
    # Other bels (e.g. extra xc7 routing bels) can be ignored for nextpnr porpoises
    return -1
  end
  default_z
end

def get_bel_type_override(bt)
  if bt.end_with?("6LUT") || bt == "LUT_OR_MEM6" || bt == "LUT6"
    return "SLICE_LUTX"
  elsif bt.end_with?("5LUT") || bt == "LUT_OR_MEM5" || bt == "LUT5"
    return "SLICE_LUTX"
  elsif bt.length == 4 && bt.end_with?("FF2")
    return "SLICE_FFX"
  elsif bt.length == 3 && bt.end_with?("FF")
    return "SLICE_FFX"
  elsif bt == "FF_INIT" || bt == "REG_INIT"
    return "SLICE_FFX"
  end

  iol_parts = ["COMBUF_", "IDDR_", "IPFF_", "OPFF_", "OPTFF_", "TFF_"]
  iol_parts.each do |p|
    return "IOL_" + p.delete("_") if bt.start_with?(p)
  end
  if bt.end_with?("_VREF")
    return "IOB_VREF"
  elsif bt.end_with?("_DIFFINBUF")
    return "IOB_DIFFINBUF"
  elsif bt.start_with?("PSS_ALTO_CORE_PAD_")
    return "PSS_PAD"
  elsif bt.start_with?("LAGUNA_RX_REG") || bt.start_with?("LAGUNA_TX_REG")
    return "LAGUNA_REGX"
  elsif bt.start_with?("BSCAN")
    return "BSCAN"
  elsif bt == "BUFGCTRL_BUFGCTRL"
    return "BUFGCTRL"
  elsif bt == "RAMB18E2_U_RAMB18E2" || bt == "RAMB18E2_L_RAMB18E2"
    return "RAMB18E2_RAMB18E2"
  else
    return bt
  end
end

def include_pip(tile_type, p)
  is_xc7_logic = %w[CLBLL_L CLBLL_R CLBLM_L CLBLM_R].include?(tile_type)
  return false if p.route_thru? && p.src_wire.name.end_with?("_CE_INT")
  return false if p.route_thru? && is_xc7_logic
  return false if p.route_thru? && p.dst_wire.name.include?("TFB")
  return false if p.src_wire.name.start_with?("CLK_BUFG_R_FBG_OUT")
  return false if p.src_wire.name.include?("CLK_HROW_CK_INT")
  return false if tile_type.start_with?("HCLK_CMT") && p.dst_wire.name.include?("FREQ_REF")
  if tile_type.start_with?("CLK_HROW_TOP")
    if p.dst_wire.name.include?("CK_BUFG_CASCO") && p.src_wire.name.include?("CK_BUFG_CASCIN")
      return false
    end
  end
  if tile_type.start_with?("HCLK_IOI")
    return false if p.dst_wire.name.include?("RCLK_BEFORE_DIV") && p.src_wire.name.include?("IMUX")
    return false if p.dst_wire.name.end_with?("_DMUX") && p.src_wire.name.include?("I2IOCLK_TOP")
  end
  if tile_type.include?("IOI")
    return false if p.dst_wire.name.include?("CLKB") && p.src_wire.name.include?("IMUX22")
    return false if p.dst_wire.name.include?("OCLKB") && p.src_wire.name.include?("IOI_OCLK_")
    return false if p.dst_wire.name.include?("OCLKM") && p.src_wire.name.include?("IMUX31")
  end
  if tile_type.include?("CMT_TOP_R")
    return false if p.dst_wire.name.include?("PLLOUT_CLK_FREQ_BB_REBUFOUT")
    return false if p.dst_wire.name.include?("MMCM_CLK_FREQ_BB")
  end
  true
end

def is_global_bel(bel)
  %w[BUFGCTRL_BUFGCTRL BUFG_BUFG].include?(bel.bel_type)
end
