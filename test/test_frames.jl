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
        test_cut_frames_cascades_to_descendants()
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

    @testset "Stream Filters" begin
        test_stream_filters()
        test_frames_of_stream_on_plain_vector()
        test_stream_filters_empty()
    end

    @testset "Hierarchy Validation" begin
        test_hierarchy_validation_simple_valid_cases()
        test_hierarchy_validation_well_formed_multi_subtree()
        test_hierarchy_validation_unknown_stream()
        test_hierarchy_validation_parent_key_mismatch()
        test_hierarchy_validation_parent_rank()
        test_hierarchy_validation_parent_not_in_container()
        test_hierarchy_validation_parent_appears_later()
    end

    @testset "deleteat! with remove_children" begin
        test_deleteat_default_unchanged()
        test_deleteat_remove_children_cascades()
        test_deleteat_remove_children_preserves_siblings()
        test_deleteat_remove_children_no_descendants()
        test_deleteat_remove_children_multiple_indices()
    end

    @testset "I/O wrapping" begin
        test_save_load_returns_tambo_frames()
        test_save_load_roundtrip_with_tambo_frames()
        test_save_frames_accepts_tambo_frames()
    end

    @testset "Pretty-printing" begin
        test_show_empty()
        test_show_simple_chain()
        test_show_ensemble()
        test_show_collapses_q_runs()
        test_show_truncates_many_roots()
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
    frames = TamboFrames(Frame[gframe, mframe])
    for v in [10, 20, 30, 40, 50]
        push!(frames, Frame('Q', Dict{String,Any}("value" => v), q_parents))
    end

    cut_frames!(frames, f -> f["value"] > 25)

    surviving_q = filter(f -> f.stream == 'Q', frames)
    @test length(surviving_q) == 3
    @test all(f -> f["value"] > 25, surviving_q)
end

function test_cut_frames_preserves_gc()
    gframe = Frame('G', Dict{String,Any}("geo" => true))
    mframe = Frame('M', Dict{String,Any}("cfg" => true))
    q_parents = Dict{Char,Frame}('G' => gframe, 'M' => mframe)
    frames = TamboFrames(Frame[
        gframe,
        mframe,
        Frame('Q', Dict{String,Any}("value" => 5),  q_parents),
        Frame('Q', Dict{String,Any}("value" => 50), q_parents),
    ])

    cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 3
    @test frames[1].stream == 'G'
    @test frames[2].stream == 'M'
    @test frames[3].stream == 'Q'
    @test frames[3]["value"] == 50
end

function test_cut_frames_cascades_to_descendants()
    # Q frames with P children — cutting a Q must also remove its P descendants.
    gframe = Frame('G')
    mframe = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe))
    q_keep = Frame('Q', Dict{String,Any}("value" => 50), Dict{Char,Frame}('G' => gframe, 'M' => mframe))
    q_cut  = Frame('Q', Dict{String,Any}("value" => 5),  Dict{Char,Frame}('G' => gframe, 'M' => mframe))
    p_keep = Frame('P', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe, 'M' => mframe, 'Q' => q_keep))
    p_cut  = Frame('P', Dict{String,Any}(), Dict{Char,Frame}('G' => gframe, 'M' => mframe, 'Q' => q_cut))
    frames = TamboFrames(Frame[gframe, mframe, q_keep, p_keep, q_cut, p_cut])

    cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 4
    @test q_cut ∉ frames
    @test p_cut ∉ frames  # cascaded out via parent reference
    @test q_keep in frames
    @test p_keep in frames
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

function _make_mixed_stream_frames()
    g = Frame('G')
    c = Frame('C')
    d = Frame('D')
    m = Frame('M')
    q = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('M' => m))
    p = Frame('P')
    (g=g, c=c, d=d, m=m, q=q, p=p)
end

function test_stream_filters()
    @testset "frames_of_stream and stream-property accessors" begin
        fs = _make_mixed_stream_frames()
        tf = TamboFrames([fs.g, fs.c, fs.d, fs.m, fs.q, fs.p])

        @test frames_of_stream(tf, 'G') == [fs.g]
        @test frames_of_stream(tf, 'C') == [fs.c]
        @test frames_of_stream(tf, 'D') == [fs.d]
        @test frames_of_stream(tf, 'M') == [fs.m]
        @test frames_of_stream(tf, 'Q') == [fs.q]
        @test frames_of_stream(tf, 'P') == [fs.p]

        @test tf.g_frames == [fs.g]
        @test tf.c_frames == [fs.c]
        @test tf.d_frames == [fs.d]
        @test tf.m_frames == [fs.m]
        @test tf.q_frames == [fs.q]
        @test tf.p_frames == [fs.p]

        # Property names are discoverable for tab-completion.
        @test :q_frames in propertynames(tf)
        @test :frames in propertynames(tf)
    end
end

function test_frames_of_stream_on_plain_vector()
    @testset "frames_of_stream works on plain Vector{Frame}" begin
        fs = _make_mixed_stream_frames()
        v = Frame[fs.g, fs.c, fs.q]

        @test frames_of_stream(v, 'G') == [fs.g]
        @test frames_of_stream(v, 'C') == [fs.c]
        @test frames_of_stream(v, 'Q') == [fs.q]
    end
end

function test_stream_filters_empty()
    @testset "Empty results when no matching frames" begin
        tf = TamboFrames([Frame('G'), Frame('G')])
        @test isempty(tf.c_frames)
        @test isempty(tf.d_frames)
        @test isempty(tf.m_frames)
        @test isempty(tf.q_frames)
        @test isempty(tf.p_frames)
        @test isempty(frames_of_stream(tf, 'X'))  # arbitrary unknown letter
    end
end

function test_hierarchy_validation_simple_valid_cases()
    @testset "Empty / single-frame containers are valid" begin
        @test is_valid_hierarchy(TamboFrames())
        @test isempty(hierarchy_violations(TamboFrames()))

        @test is_valid_hierarchy(TamboFrames([Frame('G')]))

        # Defined on AbstractVector{Frame} — works on plain Vector too.
        @test is_valid_hierarchy(Frame[Frame('G')])
    end
end

function test_hierarchy_validation_well_formed_multi_subtree()
    @testset "Well-formed multi-subtree (ensemble) is valid" begin
        g1 = Frame('G')
        m1 = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g1))
        q1 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g1, 'M' => m1))
        g2 = Frame('G')
        m2 = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g2))
        q2 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g2, 'M' => m2))
        tf = TamboFrames([g1, m1, q1, g2, m2, q2])

        @test isempty(hierarchy_violations(tf))
        @test is_valid_hierarchy(tf)
    end
end

function test_hierarchy_validation_unknown_stream()
    @testset ":unknown_stream" begin
        tf = TamboFrames([Frame('X')])
        vs = hierarchy_violations(tf)
        @test length(vs) == 1
        @test vs[1].kind == :unknown_stream
        @test vs[1].idx == 1
        @test !is_valid_hierarchy(tf)
    end
end

function test_hierarchy_validation_parent_key_mismatch()
    @testset ":parent_key_mismatch" begin
        m = Frame('M')
        # 'G' key with an M-stream value (paired with proper 'M' so Q invariant passes).
        q = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => m, 'M' => m))
        tf = TamboFrames([m, q])
        vs = hierarchy_violations(tf)
        @test any(v -> v.kind == :parent_key_mismatch, vs)
    end
end

function test_hierarchy_validation_parent_rank()
    @testset ":parent_rank" begin
        m = Frame('M')
        q1 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('M' => m))
        # q2 has q1 (a Q frame) as a 'Q' parent — equal rank.
        q2 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('M' => m, 'Q' => q1))
        tf = TamboFrames([m, q1, q2])
        vs = hierarchy_violations(tf)
        @test any(v -> v.kind == :parent_rank, vs)
    end
end

function test_hierarchy_validation_parent_not_in_container()
    @testset ":parent_not_in_container" begin
        external_m = Frame('M')
        q = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('M' => external_m))
        tf = TamboFrames([q])  # external_m not included
        vs = hierarchy_violations(tf)
        @test any(v -> v.kind == :parent_not_in_container, vs)
    end
end

function test_hierarchy_validation_parent_appears_later()
    @testset ":parent_appears_later" begin
        g = Frame('G')
        m = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g))
        q = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g, 'M' => m))
        # Wrong order: child first, parents after.
        tf = TamboFrames([q, m, g])
        vs = hierarchy_violations(tf)
        @test any(v -> v.kind == :parent_appears_later, vs)
    end
end

function _make_two_subtree_ensemble()
    g1 = Frame('G')
    m1 = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g1))
    q1a = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g1, 'M' => m1))
    q1b = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g1, 'M' => m1))
    g2 = Frame('G')
    m2 = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g2))
    q2 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g2, 'M' => m2))
    (g1=g1, m1=m1, q1a=q1a, q1b=q1b, g2=g2, m2=m2, q2=q2)
end

function test_deleteat_default_unchanged()
    @testset "default behavior unchanged" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b, e.g2, e.m2, e.q2])
        deleteat!(tf, 3)  # remove q1a only
        @test length(tf) == 6
        @test tf[3] === e.q1b
    end
end

function test_deleteat_remove_children_cascades()
    @testset "cascade through full hierarchy" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b])
        deleteat!(tf, 1; remove_children=true)
        @test isempty(tf)
    end
end

function test_deleteat_remove_children_preserves_siblings()
    @testset "siblings of target subtree remain" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b, e.g2, e.m2, e.q2])
        deleteat!(tf, 1; remove_children=true)  # nuke first subtree
        @test length(tf) == 3
        @test tf[1] === e.g2
        @test tf[2] === e.m2
        @test tf[3] === e.q2
    end
end

function test_deleteat_remove_children_no_descendants()
    @testset "no descendants → just removes target" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b])
        deleteat!(tf, 3; remove_children=true)  # remove q1a (a leaf)
        @test length(tf) == 3
        @test e.q1a ∉ tf
        @test e.q1b ∈ tf  # sibling Q frame untouched
    end
end

function test_deleteat_remove_children_multiple_indices()
    @testset "multiple indices, including downstream targets" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b, e.g2, e.m2, e.q2])
        # Remove c1 and g2: c1 takes its Q's with it; g2 takes c2 and q2.
        deleteat!(tf, [2, 5]; remove_children=true)
        @test length(tf) == 1
        @test tf[1] === e.g1
    end
end

function _make_small_save_load_frames()
    g = Frame('G', Dict{String,Any}("site" => "demo"))
    m = Frame('M', Dict{String,Any}("run" => 7), Dict{Char,Frame}('G' => g))
    q_parents = Dict{Char,Frame}('G' => g, 'M' => m)
    q1 = Frame('Q', Dict{String,Any}("event_id" => 1), q_parents)
    q2 = Frame('Q', Dict{String,Any}("event_id" => 2), q_parents)
    Frame[g, m, q1, q2]
end

function test_save_load_returns_tambo_frames()
    @testset "load_frames returns a TamboFrames" begin
        path = tempname() * ".jld2"
        save_frames(path, _make_small_save_load_frames(), streams=('G','M','Q'))
        loaded = load_frames(path)
        rm(path)

        @test loaded isa TamboFrames
        @test loaded isa AbstractVector{Frame}
    end
end

function test_save_load_roundtrip_with_tambo_frames()
    @testset "round-trip via TamboFrames preserves structure" begin
        original = TamboFrames(_make_small_save_load_frames())
        path = tempname() * ".jld2"
        save_frames(path, original, streams=('G','M','Q'))
        loaded = load_frames(path)
        rm(path)

        # Counts per stream preserved.
        @test length(loaded.g_frames) == length(original.g_frames)
        @test length(loaded.m_frames) == length(original.m_frames)
        @test length(loaded.q_frames) == length(original.q_frames)

        # Q-frame data preserved (and parent inheritance still works after reload).
        loaded_q1 = first(loaded.q_frames)
        @test loaded_q1["event_id"] == 1
        @test loaded_q1["run"] == 7      # inherited from M parent
        @test loaded_q1["site"] == "demo" # inherited from G parent
    end
end

function test_save_frames_accepts_tambo_frames()
    @testset "save_frames accepts TamboFrames directly" begin
        tf = TamboFrames(_make_small_save_load_frames())
        path = tempname() * ".jld2"
        save_frames(path, tf, streams=('G','M','Q'))   # no manual unwrap
        @test isfile(path)
        loaded = load_frames(path)
        rm(path)
        @test length(loaded) == length(tf)
    end
end

_show_lines(tf) = split(rstrip(sprint(show, MIME("text/plain"), tf)), '\n')

function test_show_empty()
    @testset "empty TamboFrames" begin
        @test sprint(show, MIME("text/plain"), TamboFrames()) == "TamboFrames ()\n"
    end
end

function test_show_simple_chain()
    @testset "G → M → Q chain" begin
        g = Frame('G')
        m = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g))
        q1 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g, 'M' => m))
        q2 = Frame('Q', Dict{String,Any}(), Dict{Char,Frame}('G' => g, 'M' => m))
        tf = TamboFrames([g, m, q1, q2])
        @test _show_lines(tf) == [
            "TamboFrames (1 G, 1 M, 2 Q)",
            "└─ G → M → Q × 2",
        ]
    end
end

function test_show_ensemble()
    @testset "two-subtree ensemble" begin
        e = _make_two_subtree_ensemble()
        tf = TamboFrames([e.g1, e.m1, e.q1a, e.q1b, e.g2, e.m2, e.q2])
        @test _show_lines(tf) == [
            "TamboFrames (2 G, 2 M, 3 Q)",
            "├─ G → M → Q × 2",
            "└─ G → M → Q",
        ]
    end
end

function test_show_collapses_q_runs()
    @testset "long Q runs collapse to count" begin
        g = Frame('G')
        m = Frame('M', Dict{String,Any}(), Dict{Char,Frame}('G' => g))
        q_parents = Dict{Char,Frame}('G' => g, 'M' => m)
        qs = [Frame('Q', Dict{String,Any}(), q_parents) for _ in 1:50]
        tf = TamboFrames([g, m, qs...])
        @test _show_lines(tf) == [
            "TamboFrames (1 G, 1 M, 50 Q)",
            "└─ G → M → Q × 50",
        ]
    end
end

function test_show_truncates_many_roots()
    @testset "more than _CHILDREN_CAP roots truncates" begin
        # 5 standalone G frames at root level.
        gs = [Frame('G') for _ in 1:5]
        tf = TamboFrames(gs)
        @test _show_lines(tf) == [
            "TamboFrames (5 G)",
            "├─ G",
            "├─ G",
            "├─ G",
            "└─ … (2 more G)",
        ]
    end
end
