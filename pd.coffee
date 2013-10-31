fs = require 'fs'
pnglib = require "./pnglib"
seedRandom = require 'seed-random'

SHAPES = [
  """
  111111111111
  122222222221
  122222222221
  122222222221
  111111112221
         12221
         12221
         12221
         12221
         12221
         12221
         11111
  """
  """
  111111111111
  122222222221
  122222222221
  122222222221
  122211111111
  12221
  12221
  12221
  12221
  12221
  12221
  11111
  """
  """
  11111
  12221
  12221
  12221
  12221
  12221
  12221
  122211111111
  122222222221
  122222222221
  122222222221
  111111111111
  """
  """
         11111
         12221
         12221
         12221
         12221
         12221
         12221
  111111112221
  122222222221
  122222222221
  122222222221
  111111111111
  """
  """
  1111111111111111111111111111
   1122222222222222222222222211
    1122222222222222222222222211
     1122222222222222222222222211
      1122222222222222222222222211
       1122222222222222222222222211
        1122222222222222222222222211
         1122222222222222222222222211
          1122222222222222222222222211
           1122222222222222222222222211
            1111111111111111111111111111
  """
]

valueToColor = (p, v) ->
  switch
    when v == 1 then return p.color 32, 32, 32
    when v == 2 then return p.color 192, 0, 0
    when v == 3 then return p.color 255, 200, 255
    when v == 4 then return p.color 200, 255, 200
    when v >= 5 then return p.color 0, 5 + Math.min(240, 15 + (v * 2)), 15 + Math.min(240, (Math.max(0, v-256) * 2))
  return p.color 0, 0, 0

class Rect
  constructor: (@l, @t, @r, @b) ->

  w: -> @r - @l
  h: -> @b - @t
  area: -> @w() * @h()
  aspect: ->
    if @h() > 0
      return @w() / @h()
    else
      return 0

  squareness: ->
    return Math.abs(@w() - @h())

  clone: ->
    return new Rect(@l, @t, @r, @b)

  expand: (r) ->
    if @area()
      @l = r.l if @l > r.l
      @t = r.t if @t > r.t
      @r = r.r if @r < r.r
      @b = r.b if @b < r.b
    else
      # special case, bbox is empty. Replace contents!
      @l = r.l
      @t = r.t
      @r = r.r
      @b = r.b

  toString: -> "{ (#{@l}, #{@t}) -> (#{@r}, #{@b}) #{@w()}x#{@h()}, area: #{@area()}, aspect: #{@aspect()}, squareness: #{@squareness()} }"

class RoomTemplate
  constructor: (@width, @height, @color) ->
    @grid = new Buffer(@width * @height)
    @generateShape()

  generateShape: ->
    for i in [0...@width]
      for j in [0...@height]
        @set(i, j, @color)
    for i in [0...@width]
      @set(i, 0, 1)
      @set(i, @height - 1, 1)
    for j in [0...@height]
      @set(0, j, 1)
      @set(@width - 1, j, 1)

  rect: (x, y) ->
    return new Rect x, y, x + @width, y + @height

  set: (i, j, v) ->
    @grid[i + (j * @width)] = v

  place: (map, x, y) ->
    for i in [0...@width]
      for j in [0...@height]
        v = @grid[i + (j * @width)]
        map.grid[x + i + ((y + j) * map.width)] = v if v

  fits: (map, x, y) ->
    for i in [0...@width]
      for j in [0...@height]
        mv = map.grid[x + i + ((y + j) * map.width)]
        sv = @grid[i + (j * @width)]
        if mv > 0 and sv > 0 and (mv != 1 or sv != 1)
          return false
    return true

  measure: (map, x, y) ->
    bboxTemp = map.bbox.clone()
    bboxTemp.expand @rect(x, y)
    [bboxTemp.area(), bboxTemp.squareness()]

  findBestSpot: (map) ->
    minSquareness = Math.max map.width, map.height
    minArea = map.width * map.height
    minX = -1
    minY = -1
    for i in [0 ... map.width - @width]
      for j in [0 ... map.height - @height]
        if @fits(map, i, j)
          [area, squareness] = @measure map, i, j
          # console.log "(#{i}, #{j}) area: #{area}, squareness #{squareness}"
          if area <= minArea and squareness <= minSquareness
            # console.log "(#{i}, #{j}) BETTER FIT area: #{area}, squareness #{squareness}"
            minArea = area
            minSquareness = squareness
            minX = i
            minY = j
    return [minX, minY]

class ShapeRoomTemplate extends RoomTemplate
  constructor: (shape, color) ->
    @lines = shape.split("\n")
    w = 0
    for line in @lines
      w = Math.max(w, line.length)
    @width = w
    @height = @lines.length
    super @width, @height, color

  generateShape: ->
    for j in [0...@height]
      for i in [0...@width]
        @set(i, j, 0)
    i = 0
    j = 0
    for line in @lines
      for c in line.split("")
        color = switch c
          when '1' then 1
          when '2' then @color
          else 0
        if color
          @set(i, j, color)
        i++
      j++
      i = 0

class Room
  constructor: (@rect) ->
    console.log "room created #{@rect}"

class Map
  constructor: (@width, @height, @seed) ->
    @randReset()
    @grid = new Buffer(@width * @height)
    @bbox = new Rect 0, 0, 0, 0
    @rooms = []

    for j in [0...H]
      for i in [0...W]
        @set(i, j, 0)

  randReset: ->
    @rng = seedRandom(@seed)

  rand: (v) ->
    return Math.floor(@rng() * v)

  outputPNG: ->
    GRIDSIZE = 10
    p = new pnglib GRIDSIZE * @width, GRIDSIZE * @height, 256
    background = p.color 0, 0, 0, 255

    for j in [0...@height]
      for i in [0...@width]
        c = valueToColor(p, @grid[i + (j * @width)])
        for a in [0...GRIDSIZE]
          for b in [0...GRIDSIZE]
            p.buffer[p.index((i * GRIDSIZE) + a, (j * GRIDSIZE) + b)] = if (a and b) then c else background

    fs.writeFile('output.html', '<img src="data:image/png;base64,'+p.getBase64()+'">')

  set: (i, j, v) ->
    @grid[i + (j * @width)] = v

  get: (i, j) ->
    if i >= 0 and i < @width and j >= 0 and j < @height
      return @grid[i + (j * @width)]
    return 0

  addRoom: (roomTemplate, x, y) ->
    console.log "placing room at #{x}, #{y}"
    roomTemplate.place this, x, y
    r = roomTemplate.rect(x, y)
    @rooms.push new Room r
    @bbox.expand(r)
    console.log "new map bbox #{@bbox}"

  randomRoomTemplate: (color) ->
    r = @rand(100)
    switch
      when r > 90 then return new ShapeRoomTemplate SHAPES[@rand(SHAPES.length)], color
    return new RoomTemplate 4 + @rand(5), 4 + @rand(5), color

  generateRoom: (color) ->
    roomTemplate = @randomRoomTemplate color
    if @rooms.length == 0
      x = Math.floor((@width / 2) - (roomTemplate.width / 2))
      y = Math.floor((@height / 2) - (roomTemplate.height / 2))
      @addRoom roomTemplate, x, y
    else
      [x, y] = roomTemplate.findBestSpot(this)
      if x < 0
        return false
      @addRoom roomTemplate, x, y

    return true

  generateRooms: (count) ->
    @randReset()
    for i in [0...count]
      @generateRoom i+5

  doorEligible: (x, y) ->
    wallNeighbors = 0
    roomsSeen = {}
    values = [
      @get(x + 1, y)
      @get(x - 1, y)
      @get(x, y + 1)
      @get(x, y - 1)
    ]
    for v in values
      if v
        if v == 1
          wallNeighbors++
        else if v != 2
          roomsSeen[v] = 1
    rooms = Object.keys(roomsSeen).sort (a, b) -> a-b
    roomCount = rooms.length
    if wallNeighbors == 2 and roomCount == 2
      console.log "rooms: #{rooms}"
      if @get(x + 1, y) == @get(x - 1, y) or @get(x, y + 1) == @get(x, y - 1)
        return rooms
    return [-1, -1]

  generateDoors: ->
    connectedRooms = {}
    for j in [0...@height]
      for i in [0...@width]
        [fromRoom, toRoom] = @doorEligible(i, j)
        if fromRoom != -1
          doorKey = "#{fromRoom}-#{toRoom}"
          if !connectedRooms[doorKey] or @rand(5) > 0
            if connectedRooms[doorKey]
              @grid[connectedRooms[doorKey][0] + (connectedRooms[doorKey][1] * @width)] = 1
            console.log "connecting room #{fromRoom} to #{toRoom}"
            @grid[i + (j * @width)] = 2
            connectedRooms[doorKey] = [i, j]

W = 80
H = 80
currentSeed = 13
map = new Map W, H, currentSeed

map.generateRooms(200)
map.generateDoors()
map.outputPNG()
