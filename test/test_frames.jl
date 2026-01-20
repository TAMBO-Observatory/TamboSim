"""
Tests for the Frame data structure.
"""

# ============================================================================
# Frame type for testing
# ============================================================================

struct TestFrame
    data::Dict{String, Any}
    parent::Union{Nothing, TestFrame}
    type::Char
    TestFrame() = new(Dict{String, Any}(), nothing, 'T')
    TestFrame(data::Dict) = new(data, nothing, 'T')
    TestFrame(data::Dict, type::Char) = new(data, nothing, type)
    TestFrame(data::Dict, parent::TestFrame, type::Char) = new(data, parent, type)
end

function Base.getindex(frame::TestFrame, key::String)
    if haskey(frame.data, key)
        return frame.data[key]
    elseif isnothing(frame.parent)
        throw(KeyError(key))
    else
        return frame.parent[key]
    end
end

function Base.setindex!(frame::TestFrame, value, key::String)
    frame.data[key] = value
end

function Base.haskey(frame::TestFrame, key::String)
    if haskey(frame.data, key)
        return true
    elseif isnothing(frame.parent)
        return false
    else
        return haskey(frame.parent, key)
    end
end

function Base.keys(frame::TestFrame)
    if isnothing(frame.parent)
        return keys(frame.data)
    else
        return union(keys(frame.data), keys(frame.parent))
    end
end

function Base.getkey(frame::TestFrame, k::String, default)
    if haskey(frame, k)
        return frame[k]
    else
        return default
    end
end

function test_cut_frames!(frames::Vector{TestFrame}, fxn::Function)
    idx = 1
    while idx <= length(frames)
        frame = frames[idx]
        if !fxn(frame)
            deleteat!(frames, idx)
            continue
        end
        idx += 1
    end
end

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
    f = TestFrame()

    @test isempty(f.data)
    @test isnothing(f.parent)
end

function test_frame_with_data()
    data = Dict("key1" => 1, "key2" => "value")
    f = TestFrame(data)

    @test f.data == data
    @test f["key1"] == 1
    @test f["key2"] == "value"
end

function test_frame_with_parent()
    parent = TestFrame(Dict("parent_key" => 100))
    child = TestFrame(Dict("child_key" => 200), parent, 'C')

    @test child.parent == parent
    @test child.type == 'C'
    @test child["child_key"] == 200
    @test child["parent_key"] == 100
end

function test_frame_getindex()
    data = Dict("key" => 42)
    f = TestFrame(data)

    @test f["key"] == 42
    @test_throws KeyError f["nonexistent"]
end

function test_frame_setindex()
    f = TestFrame()

    f["new_key"] = "new_value"

    @test f["new_key"] == "new_value"
    @test haskey(f, "new_key")
end

function test_frame_haskey()
    parent = TestFrame(Dict("parent_key" => 1))
    child = TestFrame(Dict("child_key" => 2), parent, 'C')

    @test haskey(child, "child_key")
    @test haskey(child, "parent_key")
    @test !haskey(child, "nonexistent")
end

function test_frame_keys()
    parent = TestFrame(Dict("a" => 1, "b" => 2))
    child = TestFrame(Dict("c" => 3, "d" => 4), parent, 'C')

    all_keys = keys(child)

    @test "a" in all_keys
    @test "b" in all_keys
    @test "c" in all_keys
    @test "d" in all_keys
end

function test_frame_getkey_default()
    f = TestFrame(Dict("exists" => 10))

    @test getkey(f, "exists", 0) == 10
    @test getkey(f, "nonexistent", 0) == 0
end

function test_frame_parent_lookup()
    grandparent = TestFrame(Dict("level" => "grandparent", "gp_key" => 100))
    parent = TestFrame(Dict("level" => "parent", "p_key" => 200), grandparent, 'P')
    child = TestFrame(Dict("level" => "child", "c_key" => 300), parent, 'C')

    @test child["gp_key"] == 100
    @test child["p_key"] == 200
    @test child["c_key"] == 300
end

function test_frame_override_parent()
    parent = TestFrame(Dict("key" => "parent_value"))
    child = TestFrame(Dict("key" => "child_value"), parent, 'C')

    @test child["key"] == "child_value"
    @test parent["key"] == "parent_value"
end

function test_frame_multi_level_hierarchy()
    f1 = TestFrame(Dict("level1" => true))
    f2 = TestFrame(Dict("level2" => true), f1, 'A')
    f3 = TestFrame(Dict("level3" => true), f2, 'B')
    f4 = TestFrame(Dict("level4" => true), f3, 'C')

    @test f4["level1"] == true
    @test f4["level2"] == true
    @test f4["level3"] == true
    @test f4["level4"] == true
end

function test_cut_frames()
    frames = [
        TestFrame(Dict("value" => 10)),
        TestFrame(Dict("value" => 20)),
        TestFrame(Dict("value" => 30)),
        TestFrame(Dict("value" => 40)),
        TestFrame(Dict("value" => 50))
    ]

    test_cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 3
    @test all(f -> f["value"] > 25, frames)
end
