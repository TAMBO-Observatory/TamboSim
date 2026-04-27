"""
Tests for the Frame data structure.

These tests use the actual Tambo types from src/ to ensure code coverage.
"""

# ============================================================================
# Test functions
# ============================================================================

function run_frame_tests()
    @testset "Frame Construction" begin
        test_frame_empty_construction()
        test_frame_with_data()
        test_frame_with_parent()
    end

    @testset "Frame Access" begin
        test_frame_getindex()
        test_frame_setindex()
        test_frame_haskey()
        test_frame_keys()
        test_frame_getkey_default()
    end

    @testset "Frame Hierarchy" begin
        test_frame_parent_lookup()
        test_frame_override_parent()
        test_frame_multi_level_hierarchy()
    end

    @testset "Frame Utilities" begin
        test_cut_frames()
    end
end

function test_frame_empty_construction()
    f = Frame()

    @test isempty(f.data)
    @test isnothing(f.parent)
    @test f.type == 'T'
end

function test_frame_with_data()
    data = Dict("key1" => 1, "key2" => "value")
    f = Frame(data)

    @test f.data == data
    @test f["key1"] == 1
    @test f["key2"] == "value"
end

function test_frame_with_parent()
    parent = Frame(Dict("parent_key" => 100))
    child = Frame(Dict("child_key" => 200), parent, 'C')

    @test child.parent == parent
    @test child.type == 'C'
    @test child["child_key"] == 200
    @test child["parent_key"] == 100
end

function test_frame_getindex()
    data = Dict("key" => 42)
    f = Frame(data)

    @test f["key"] == 42
    @test_throws KeyError f["nonexistent"]
end

function test_frame_setindex()
    f = Frame()

    f["new_key"] = "new_value"

    @test f["new_key"] == "new_value"
    @test haskey(f, "new_key")
end

function test_frame_haskey()
    parent = Frame(Dict("parent_key" => 1))
    child = Frame(Dict("child_key" => 2), parent, 'C')

    @test haskey(child, "child_key")
    @test haskey(child, "parent_key")
    @test !haskey(child, "nonexistent")
end

function test_frame_keys()
    parent = Frame(Dict("a" => 1, "b" => 2))
    child = Frame(Dict("c" => 3, "d" => 4), parent, 'C')

    all_keys = keys(child)

    @test "a" in all_keys
    @test "b" in all_keys
    @test "c" in all_keys
    @test "d" in all_keys
end

function test_frame_getkey_default()
    f = Frame(Dict("exists" => 10))

    @test getkey(f, "exists", 0) == 10
    @test getkey(f, "nonexistent", 0) == 0
end

function test_frame_parent_lookup()
    grandparent = Frame(Dict("level" => "grandparent", "gp_key" => 100))
    parent = Frame(Dict("level" => "parent", "p_key" => 200), grandparent, 'P')
    child = Frame(Dict("level" => "child", "c_key" => 300), parent, 'C')

    @test child["gp_key"] == 100
    @test child["p_key"] == 200
    @test child["c_key"] == 300
end

function test_frame_override_parent()
    parent = Frame(Dict("key" => "parent_value"))
    child = Frame(Dict("key" => "child_value"), parent, 'C')

    @test child["key"] == "child_value"
    @test parent["key"] == "parent_value"
end

function test_frame_multi_level_hierarchy()
    f1 = Frame(Dict("level1" => true))
    f2 = Frame(Dict("level2" => true), f1, 'A')
    f3 = Frame(Dict("level3" => true), f2, 'B')
    f4 = Frame(Dict("level4" => true), f3, 'C')

    @test f4["level1"] == true
    @test f4["level2"] == true
    @test f4["level3"] == true
    @test f4["level4"] == true
end

function test_cut_frames()
    frames = [
        Frame(Dict("value" => 10)),
        Frame(Dict("value" => 20)),
        Frame(Dict("value" => 30)),
        Frame(Dict("value" => 40)),
        Frame(Dict("value" => 50))
    ]

    cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 3
    @test all(f -> f["value"] > 25, frames)
end
