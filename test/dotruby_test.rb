# frozen_string_literal: true

require "minitest/autorun"
require_relative "../dotruby"

class DotrubyTest < Minitest::Test
  def test_rasterize_accepts_angle_explicitly
    assert_equal 5, method(:rasterize).arity
  end

  def test_faces_are_plain_triangles
    assert_equal 60, FACES.size
    assert FACES.all? { |face| face.size == 3 && face.all? { |point| point.size == 3 } }
  end
end
