require 'json'

def apply_tileconn(f, d)
  merge_nodes = lambda do |a, b|
    b.wires.each do |bwire|
      bwire.tile.wire_to_node[bwire.index] = a
      a.wires << bwire
    end
    b.wires = []
  end

  tj = JSON.load(f)
  # Restructure to tiletype -> coord offset -> type -> wire_pairs
  ttn = {}
  tj.each do |entry|
    tile0, tile1 = entry["tile_types"]
    dx, dy = entry["grid_deltas"]
    ttn[tile0] ||= {}
    ttn[tile0][[dx, dy]] ||= {}
    ttn[tile0][[dx, dy]][tile1] = entry["wire_pairs"]
  end

  d.tiles.each do |tile|
    tt = tile.tile_type
    next unless ttn.key?(tt)

    # Search the neighborhood around a tile
    ttn[tt].sort.each do |dxy, nd|
      nx = tile.x + dxy[0]
      ny = tile.y + dxy[1]
      next unless d.tiles_by_xy.key?([nx, ny])

      ntile = d.tiles_by_xy[[nx, ny]]
      ntt = ntile.tile_type
      next unless nd.key?(ntt)

      # Found a pair with connections
      wc = nd[ntt]
      wc.each do |wirea, wireb|
        merge_nodes.call(tile.wire(wirea).node, ntile.wire(wireb).node)
      end
    end
  end
end
