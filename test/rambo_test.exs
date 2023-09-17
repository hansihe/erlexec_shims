defmodule RamboTest do
  use ExUnit.Case
  doctest Rambo

  test "greets the world" do
    assert Rambo.hello() == :world
  end
end
