defmodule ElixirScope.DistributedTest do
  use ExUnit.Case
  doctest ElixirScope.Distributed

  test "greets the world" do
    assert ElixirScope.Distributed.hello() == :world
  end
end
