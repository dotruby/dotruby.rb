# frozen_string_literal: true

WIDTH = 80
HEIGHT = 40
CAM_DIST = 5.0
PHI = (1 + Math.sqrt(5)) / 2.0

def normalize(vector)
  length = Math.sqrt(vector.sum { |component| component * component })
  vector.map { |component| component / length }
end

def cross(a, b)
  [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0]
  ]
end

def sub(a, b)
  [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
end

def dot(a, b)
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
end

def add(a, b)
  [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
end

def mul(vector, scalar)
  [vector[0] * scalar, vector[1] * scalar, vector[2] * scalar]
end

def average(points)
  sum = points.reduce([0.0, 0.0, 0.0]) { |total, point| add(total, point) }
  mul(sum, 1.0 / points.size)
end

def ordered_around(axis, points)
  up = (axis[1].abs < 0.9) ? [0.0, 1.0, 0.0] : [1.0, 0.0, 0.0]
  u = normalize(cross(up, axis))
  v = cross(axis, u)

  points.sort_by do |point|
    rel = sub(point, mul(axis, dot(point, axis)))
    Math.atan2(dot(rel, v), dot(rel, u))
  end
end

LIGHT = normalize([0.35, 0.7, -0.55]).freeze

ICO_VERTS = [
  [-1, PHI, 0], [1, PHI, 0], [-1, -PHI, 0], [1, -PHI, 0],
  [0, -1, PHI], [0, 1, PHI], [0, -1, -PHI], [0, 1, -PHI],
  [PHI, 0, -1], [PHI, 0, 1], [-PHI, 0, -1], [-PHI, 0, 1]
].map { |point| normalize(point).freeze }.freeze

ICO_FACES = [
  [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
  [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
  [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
  [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
].map(&:freeze).freeze

def build_faces
  dodeca = ICO_FACES.map { |face| normalize(average(face.map { |index| ICO_VERTS[index] })) }

  ICO_VERTS.each_with_index.each_with_object([]) do |(vertex, vertex_index), faces|
    pentagon = dodeca_pentagon(dodeca, vertex, vertex_index)
    pentagon.each_with_index do |point, index|
      faces << [vertex, pentagon[(index + 1) % pentagon.size], point]
    end
  end
end

def dodeca_pentagon(dodeca, vertex, vertex_index)
  pentagon = ICO_FACES.each_with_index.filter_map do |face, face_index|
    dodeca[face_index] if face.include?(vertex_index)
  end

  ordered_around(vertex, pentagon)
end

FACES = build_faces.freeze
abort "expected 60 faces, got #{FACES.size}" unless FACES.size == 60

def rotate_y(point, angle)
  x, y, z = point
  cosine = Math.cos(angle)
  sine = Math.sin(angle)
  [x * cosine + z * sine, y, -x * sine + z * cosine]
end

def rotate_x(point, angle)
  x, y, z = point
  cosine = Math.cos(angle)
  sine = Math.sin(angle)
  [x, y * cosine - z * sine, y * sine + z * cosine]
end

PALETTE = " .:-=+*#%@".chars.freeze
EDGE = "\e[38;2;24;22;42m"

def shade_to_char(brightness)
  normalized = brightness.clamp(0.0, 1.0)
  PALETTE[(normalized * (PALETTE.size - 1)).round]
end

def shade_to_ansi(point, brightness)
  normalized = brightness.clamp(0.0, 1.0)
  glow = ((point[1] + 1.0) / 2.0).clamp(0.0, 1.0)
  red = (65 + 112 * normalized + 38 * glow * normalized).to_i.clamp(0, 255)
  green = (4 + 14 * normalized + 42 * glow * normalized).to_i.clamp(0, 255)
  blue = (2 + 2 * normalized + 18 * glow * normalized).to_i.clamp(0, 255)
  red, green, blue = [177, 18, 4] if (normalized - 0.65).abs < 0.001
  "\e[38;2;#{red};#{green};#{blue}m"
end

def draw_edge(a, b, zbuffer, chars, colors)
  steps = [(a[0] - b[0]).abs, (a[1] - b[1]).abs].max.ceil
  return if steps.zero?

  (0..steps).each do |step|
    draw_edge_point(a, b, zbuffer, chars, colors, step.to_f / steps)
  end
end

def draw_edge_point(a, b, zbuffer, chars, colors, amount)
  x = (a[0] + (b[0] - a[0]) * amount).round
  y = (a[1] + (b[1] - a[1]) * amount).round
  return unless x.between?(0, WIDTH - 1) && y.between?(0, HEIGHT - 1)

  z = a[2] + (b[2] - a[2]) * amount
  index = y * WIDTH + x
  return unless z <= zbuffer[index] + 0.04

  chars[index] = ":"
  colors[index] = EDGE
end

def project(point)
  x, y, z = point
  scale = 3.95 * WIDTH / (z + CAM_DIST) / 2.2
  [x * scale + WIDTH / 2.0, -y * scale * 0.58 + HEIGHT / 2.0, z]
end

def rasterize(face, angle, zbuffer, chars, colors)
  points = face.map { |point| rotate_y(rotate_x(point, 0.58), angle) }
  screen = points.map { |point| project(point) }
  fill_triangle(points, screen, zbuffer, chars, colors)
  draw_edge(screen[0], screen[1], zbuffer, chars, colors)
  draw_edge(screen[1], screen[2], zbuffer, chars, colors)
  draw_edge(screen[2], screen[0], zbuffer, chars, colors)
end

def fill_triangle(points, screen, zbuffer, chars, colors)
  x0, y0 = screen[0]
  x1, y1 = screen[1]
  x2, y2 = screen[2]
  determinant = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
  return if determinant.abs < 1e-9

  triangle_bounds(screen).then do |min_x, max_x, min_y, max_y|
    fill_bounds(points, [x0, y0, x1, y1, x2, y2, determinant], [min_x, max_x, min_y, max_y], zbuffer, chars, colors)
  end
end

def triangle_bounds(screen)
  xs = screen.map(&:first)
  ys = screen.map { |point| point[1] }
  [[xs.min.floor, 0].max, [xs.max.ceil, WIDTH - 1].min, [ys.min.floor, 0].max, [ys.max.ceil, HEIGHT - 1].min]
end

def fill_bounds(points, triangle, bounds, zbuffer, chars, colors)
  min_x, max_x, min_y, max_y = bounds
  (min_y..max_y).each do |pixel_y|
    (min_x..max_x).each do |pixel_x|
      fill_pixel(points, triangle, zbuffer, chars, colors, pixel_x, pixel_y)
    end
  end
end

def fill_pixel(points, triangle, zbuffer, chars, colors, pixel_x, pixel_y)
  a, b, c = barycentric(triangle, pixel_x, pixel_y)
  return unless a >= -0.001 && b >= -0.001 && c >= -0.001

  depth = a * points[0][2] + b * points[1][2] + c * points[2][2]
  index = pixel_y * WIDTH + pixel_x
  return unless depth < zbuffer[index]

  brightness = face_brightness(points)
  zbuffer[index] = depth
  chars[index] = shade_to_char(brightness)
  colors[index] = shade_to_ansi(average(points), brightness)
end

def barycentric(triangle, pixel_x, pixel_y)
  x0, y0, x1, y1, x2, y2, determinant = triangle
  a = ((x1 - pixel_x) * (y2 - pixel_y) - (x2 - pixel_x) * (y1 - pixel_y)) / determinant
  b = ((x2 - pixel_x) * (y0 - pixel_y) - (x0 - pixel_x) * (y2 - pixel_y)) / determinant
  [a, b, 1 - a - b]
end

def face_brightness(points)
  normal = normalize(cross(sub(points[2], points[0]), sub(points[1], points[0])))
  (dot(normal, LIGHT) + 1) / 2.0
end

def render_frame(angle)
  zbuffer = Array.new(WIDTH * HEIGHT, Float::INFINITY)
  chars = Array.new(WIDTH * HEIGHT, " ")
  colors = Array.new(WIDTH * HEIGHT)
  FACES.each { |face| rasterize(face, angle, zbuffer, chars, colors) }
  frame_from(chars, colors)
end

def frame_from(chars, colors)
  out = +"\e[H"
  HEIGHT.times do |y|
    (y * WIDTH...y * WIDTH + WIDTH).each { |index| out << (colors[index] || "") << chars[index] }
    out << "\e[0m\n"
  end
  out
end

def terminal_handle
  File.open("/dev/tty", "r+")
rescue SystemCallError
  nil
end

def terminal_state(tty)
  return unless tty

  state = IO.popen(["stty", "-g"], in: tty, err: File::NULL, &:read).strip
  state unless state.empty?
end

def apply_terminal_mode(tty, *mode)
  return unless tty

  system("stty", *mode, in: tty, out: File::NULL, err: File::NULL, exception: false)
end

if __FILE__ == $PROGRAM_NAME
  frame_limit = ENV["GEM_FRAMES"]&.to_i
  tty = terminal_handle
  stty_state = terminal_state(tty)
  interrupted = false
  trap("INT") { interrupted = true }
  trap("TERM") { interrupted = true }

  apply_terminal_mode(tty, "-echoctl") if stty_state
  print "\e[2J\e[?25l"
  angle = Math::PI / 10
  frame = 0

  begin
    until interrupted
      print render_frame(angle)
      angle += 0.055
      frame += 1
      break if frame_limit && frame >= frame_limit

      sleep 0.04
    end
  ensure
    print "\e[?25h\n"
    apply_terminal_mode(tty, stty_state) if stty_state
    tty&.close
  end
end
