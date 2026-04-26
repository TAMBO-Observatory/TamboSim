"""
Tests for the Frame data structure.
"""

function run_frame_tests()
    @testset "Frame Construction" begin
        test_frame_construction()
        test_frame_with_data()
        test_frame_with_parents()
        test_q_frame_requires_parents()
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
        test_frame_hierarchy_order()
        test_frame_getproperty()
    end

    @testset "Frame Utilities" begin
        test_cut_frames_q_only()
        test_cut_frames_preserves_gc()
    end

    @testset "Multi-geometry reconstruction" begin
        test_multi_geometry_parent_reset()
    end

    @testset "TamboFrames Wrapper" begin
        test_tambo_frames_construction()
        test_tambo_frames_indexing()
        test_tambo_frames_iteration()
        test_tambo_frames_mutation()
        test_tambo_frames_vcat_copy()
        test_tambo_frames_abstractvector_drop_in()
    end
end

function _make_q_frame(data=Dict{String,Any}())
    gframe = Frame('G', Dict{String,Any}())
    mframe = Frame('M', Dict{String,Any}())
    Frame('Q', data, Dict{Char,Frame}('G' => gframe, 'M' => mframe))
end

function test_frame_construction()
    f = Frame('G')
    @test isempty(f.data)
    @test isempty(f.parents)
    @test f.stream == 'G'
end

function test_frame_with_data()
    data = Dict{String,Any}("key1" => 1, "key2" => "value")
    f = Frame('M', data)
    @test f.data == data
    @test f["key1"] == 1
    @test f["key2"] == "value"
end

function test_frame_with_parents()
    gframe = Frame('G', Dict{String,Any}("earth_path" => "/tmp/earth.h5"))
    mframe = Frame('M', Dict{String,Any}("nevent" => 100))
    mframe.parents['G'] = gframe

    @test mframe["earth_path"] == "/tmp/earth.h5"
    @test mframe["nevent"] == 100
    @test mframe.stream == 'M'
    @test length(mframe.parents) == 1
end

function test_q_frame_requires_parents()
    @test_throws ErrorException Frame('Q')
    @test_throws ErrorException Frame('Q', Dict{String,Any}())
    gframe = Frame('G')
    @test_throws ErrorException Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe))
    # G parent is optional — Q frame without G parent is valid for analysis workflows
    mframe = Frame('M')
    @test Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('M' => mframe)) isa Frame
end

function test_frame_getindex()
    f = Frame('G', Dict{String,Any}("key" => 42))
    @test f["key"] == 42
    @test_throws KeyError f["nonexistent"]
end

function test_frame_setindex()
    f = Frame('G')
    f["new_key"] = "new_value"
    @test f["new_key"] == "new_value"
    @test haskey(f, "new_key")
end

function test_frame_haskey()
    gframe = Frame('G', Dict{String,Any}("parent_key" => 1))
    mframe = Frame('M', Dict{String,Any}())
    child = Frame('Q', Dict{String,Any}("child_key" => 2), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    @test haskey(child, "child_key")
    @test haskey(child, "parent_key")
    @test !haskey(child, "nonexistent")
end

function test_frame_keys()
    gframe = Frame('G', Dict{String,Any}("a" => 1, "b" => 2))
    mframe = Frame('M', Dict{String,Any}())
    child = Frame('Q', Dict{String,Any}("c" => 3, "d" => 4), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    all_keys = keys(child)
    @test "a" in all_keys
    @test "b" in all_keys
    @test "c" in all_keys
    @test "d" in all_keys
end

function test_frame_getkey_default()
    f = Frame('G', Dict{String,Any}("exists" => 10))
    @test getkey(f, "exists", 0) == 10
    @test getkey(f, "nonexistent", 0) == 0
end

function test_frame_parent_lookup()
    gframe = Frame('G', Dict{String,Any}("gp_key" => 100))
    mframe = Frame('M', Dict{String,Any}("p_key" => 200))
    mframe.parents['G'] = gframe
    qframe = Frame('Q', Dict{String,Any}("c_key" => 300), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    @test qframe["gp_key"] == 100
    @test qframe["p_key"] == 200
    @test qframe["c_key"] == 300
end

function test_frame_override_parent()
    gframe = Frame('G', Dict{String,Any}("key" => "g_value"))
    mframe = Frame('M', Dict{String,Any}())
    qframe = Frame('Q', Dict{String,Any}("key" => "q_value"), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    @test qframe["key"] == "q_value"
    @test gframe["key"] == "g_value"
end

function test_frame_hierarchy_order()
    gframe = Frame('G', Dict{String,Any}("shared" => "from_g"))
    mframe = Frame('M', Dict{String,Any}("shared" => "from_m"))
    qframe = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    @test qframe["shared"] == "from_g"
end

function test_frame_getproperty()
    gframe = Frame('G', Dict{String,Any}("geo" => true))
    mframe = Frame('M', Dict{String,Any}("cfg" => true))
    qframe = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe, 'M' => mframe))

    @test qframe.gframe === gframe
    @test qframe.mframe === mframe
    @test_throws ErrorException Frame('G').gframe
end

function test_cut_frames_q_only()
    gframe = Frame('G', Dict{String,Any}("geo" => true))
    mframe = Frame('M', Dict{String,Any}("cfg" => true))
    q_parents = Dict{Char,Frame}('G' => gframe, 'M' => mframe)
    frames = Frame[gframe, mframe]
    for v in [10, 20, 30, 40, 50]
        push!(frames, Frame('Q', Dict{String,Any}("value" => v), q_parents))
    end

    cut_frames!(frames, f -> f["value"] > 25)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 3
    @test all(f -> f["value"] > 25, q_frames)
end

function test_cut_frames_preserves_gc()
    gframe = Frame('G', Dict{String,Any}("geo" => true))
    mframe = Frame('M', Dict{String,Any}("cfg" => true))
    q_parents = Dict{Char,Frame}('G' => gframe, 'M' => mframe)
    frames = Frame[
        gframe,
        mframe,
        Frame('Q', Dict{String,Any}("value" => 5),  q_parents),
        Frame('Q', Dict{String,Any}("value" => 50), q_parents),
    ]

    cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 3
    @test frames[1].stream == 'G'
    @test frames[2].stream == 'M'
    @test frames[3].stream == 'Q'
    @test frames[3]["value"] == 50
end

function test_multi_geometry_parent_reset()
    # Simulate loading ["geo1.jld2", "run1.jld2", "geo2.jld2", "run2.jld2"].
    # Q frames from run2 must have geo2 as G parent and run2's C as C parent,
    # not geo1 or run1's C.
    raw = Tuple{Char,Dict{String,Any}}[
        ('G', Dict{String,Any}("site" => "geo1")),
        ('M', Dict{String,Any}("run" => "run1")),
        ('Q', Dict{String,Any}("event" => 1)),
        ('Q', Dict{String,Any}("event" => 2)),
        ('G', Dict{String,Any}("site" => "geo2")),
        ('M', Dict{String,Any}("run" => "run2")),
        ('Q', Dict{String,Any}("event" => 3)),
    ]
    frames = Tambo._reconstruct_frames(raw)

    q_frames = filter(f -> f.stream == 'Q', frames)
    run1_qs = filter(f -> f["event"] <= 2, q_frames)
    run2_qs = filter(f -> f["event"] == 3, q_frames)

    # run1 Q frames should have geo1 and run1's M
    @test all(f -> f.gframe["site"] == "geo1", run1_qs)
    @test all(f -> f.mframe["run"] == "run1", run1_qs)

    # run2 Q frames should have geo2 and run2's M — not geo1 or run1's M
    @test run2_qs[1].gframe["site"] == "geo2"
    @test run2_qs[1].mframe["run"] == "run2"
end

function test_tambo_frames_construction()
    @testset "Construction" begin
        # Empty
        tf = TamboFrames()
        @test length(tf) == 0
        @test isempty(tf)
        @test tf isa AbstractVector{Frame}

        # From Vector
        f1 = Frame('G')
        f2 = Frame('G')
        tf = TamboFrames([f1, f2])
        @test length(tf) == 2
        @test tf[1] === f1
        @test tf[2] === f2

        # Vararg
        tf = TamboFrames(f1, f2)
        @test length(tf) == 2
        @test tf[1] === f1
    end
end

function test_tambo_frames_indexing()
    @testset "Indexing" begin
        f1 = Frame('G')
        f2 = Frame('G')
        f3 = Frame('G')
        tf = TamboFrames([f1, f2, f3])

        @test tf[1] === f1
        @test tf[end] === f3
        @test tf[1:2] == [f1, f2]
        @test firstindex(tf) == 1
        @test lastindex(tf) == 3

        # setindex!
        f_new = Frame('G')
        tf[2] = f_new
        @test tf[2] === f_new

        # IndexStyle
        @test IndexStyle(typeof(tf)) == IndexLinear()
    end
end

function test_tambo_frames_iteration()
    @testset "Iteration" begin
        f1 = Frame('G')
        f2 = Frame('G')
        f3 = Frame('G')
        tf = TamboFrames([f1, f2, f3])

        collected = [f for f in tf]
        @test collected == [f1, f2, f3]

        @test eltype(tf) == Frame
        @test eltype(typeof(tf)) == Frame
        @test size(tf) == (3,)
    end
end

function test_tambo_frames_mutation()
    @testset "Mutation" begin
        tf = TamboFrames()
        f1 = Frame('G')
        f2 = Frame('G')
        f3 = Frame('G')

        # push! returns the container (chainable)
        ret = push!(tf, f1)
        @test ret === tf
        @test length(tf) == 1
        @test tf[1] === f1

        # append!
        append!(tf, [f2, f3])
        @test length(tf) == 3

        # deleteat!
        deleteat!(tf, 2)
        @test length(tf) == 2
        @test tf[1] === f1
        @test tf[2] === f3

        # empty!
        empty!(tf)
        @test length(tf) == 0
        @test isempty(tf)
    end
end

function test_tambo_frames_vcat_copy()
    @testset "vcat and copy" begin
        f1 = Frame('G')
        f2 = Frame('G')
        f3 = Frame('G')

        tf1 = TamboFrames([f1, f2])
        tf2 = TamboFrames([f3])

        # vcat preserves TamboFrames type
        combined = vcat(tf1, tf2)
        @test combined isa TamboFrames
        @test length(combined) == 3
        @test combined[1] === f1
        @test combined[3] === f3

        # copy preserves type and is independent
        c = copy(tf1)
        @test c isa TamboFrames
        @test length(c) == 2
        push!(c, f3)
        @test length(c) == 3
        @test length(tf1) == 2  # original unchanged
    end
end

function test_tambo_frames_abstractvector_drop_in()
    @testset "AbstractVector drop-in" begin
        # Functions written against AbstractVector{Frame} should accept TamboFrames.
        f1 = Frame('G')
        f2 = Frame('G')
        f3 = Frame('G')
        tf = TamboFrames([f1, f2, f3])

        # filter, map, length, etc. all derive from AbstractArray
        gframes = filter(f -> f.stream == 'G', tf)
        @test length(gframes) == 3

        # Can be passed to a function typed as AbstractVector{Frame}
        f_count(v::AbstractVector{Frame}) = length(v)
        @test f_count(tf) == 3
    end
end
