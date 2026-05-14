include("testsetup.jl")
using HDF5

import TamboSim: build_gcd_bundle, make_watertight, dump_to_h5, dump_to_ply

"""
Tests for earth.jl: build_gcd_bundle, make_watertight, dump_to_h5, dump_to_ply.
"""

# =============================================================================
# Shared fixture
# =============================================================================

const _TEST_PREM_RADII = [5_000_000.0, 6_000_000.0, 6_371_000.0] .* u"m"
const _TEST_LONGLAT    = (0.0, π/2)   # North Pole — up = [0,0,1]
const _TEST_REARTH     = 6_371_000.0

"""
Build a small flat square mesh centred at the North Pole. `n` cells per side
gives `2n²` triangles and `(n+1)²` vertices. The detector region is the first
`2` faces.
"""
function _test_mesh(; n=3, half_width=10_000.0)
    lon, lat = _TEST_LONGLAT
    r     = _TEST_REARTH
    up    = TamboSim.longlat_to_cart(lon, lat)          # [0, 0, 1]
    east  = normalize([-sin(lon), cos(lon), 0.0])        # [0, 1, 0]
    north = normalize(cross(up, east))                   # [-1, 0, 0]

    xs = range(-half_width, half_width, length=n+1)
    ys = range(-half_width, half_width, length=n+1)

    n_verts = (n+1)^2
    vertices = Matrix{Float64}(undef, n_verts, 3)
    for (j, y) in enumerate(ys), (i, x) in enumerate(xs)
        idx = (j-1)*(n+1) + i
        vertices[idx, :] = up .* r .+ east .* x .+ north .* y
    end

    n_faces = 2 * n^2
    faces = Matrix{Int}(undef, n_faces, 3)
    fi = 1
    for j in 1:n, i in 1:n
        bl = (j-1)*(n+1) + i
        br, tl, tr = bl+1, bl+(n+1), bl+(n+1)+1
        faces[fi,   :] = [bl, br, tr]
        faces[fi+1, :] = [bl, tr, tl]
        fi += 2
    end

    detector = [1, 2]
    return vertices, faces, detector
end

function _test_bundle()
    verts, faces, det = _test_mesh()
    build_gcd_bundle(verts, faces, _TEST_LONGLAT, _TEST_PREM_RADII, det)
end

# =============================================================================
# PLY header helpers
# =============================================================================

function _read_ply_header(path)
    lines = String[]
    open(path) do io
        while true
            line = readline(io)
            push!(lines, line)
            line == "end_header" && break
        end
    end
    return lines
end

function _ply_vertex_count(header)
    for line in header
        startswith(line, "element vertex") && return parse(Int, split(line)[3])
    end
    return 0
end

function _ply_face_count(header)
    for line in header
        startswith(line, "element face") && return parse(Int, split(line)[3])
    end
    return 0
end

# =============================================================================
# Boundary-edge counter for make_watertight tests
# =============================================================================

function _boundary_edge_count(faces)
    edge_count = Dict{Tuple{Int,Int}, Int}()
    for i in axes(faces, 1)
        for (a, b) in ((faces[i,1], faces[i,2]),
                       (faces[i,2], faces[i,3]),
                       (faces[i,3], faces[i,1]))
            key = minmax(a, b)
            edge_count[key] = get(edge_count, key, 0) + 1
        end
    end
    return count(v -> v == 1, values(edge_count))
end

# =============================================================================
# Binary PLY parser for round-trip tests
# =============================================================================

"""
Parse a binary-little-endian PLY file written by `_serialize_corsika_ply`
and return `(vertices, faces)` where vertices are `Float64` ECEF coords and
faces are 0-based `UInt32` indices (as stored on disk).
"""
function _parse_binary_ply(path)
    open(path) do io
        nverts = 0
        nfaces = 0
        while !eof(io)
            line = readline(io)
            startswith(line, "element vertex") && (nverts = parse(Int, split(line)[3]))
            startswith(line, "element face")   && (nfaces = parse(Int, split(line)[3]))
            line == "end_header" && break
        end
        # File is row-major (x1 y1 z1 x2 y2 z2 …); read into (3, nverts) then
        # transpose so the result matches our (nverts, 3) convention.
        verts_T = Matrix{Float64}(undef, 3, nverts)
        read!(io, verts_T)
        verts = permutedims(verts_T)
        faces = Matrix{UInt32}(undef, nfaces, 3)
        for i in 1:nfaces
            n = read(io, UInt8)
            n == 0x03 || error("expected 3-vertex face, got $n")
            faces[i, 1] = ltoh(read(io, UInt32))
            faces[i, 2] = ltoh(read(io, UInt32))
            faces[i, 3] = ltoh(read(io, UInt32))
        end
        return verts, faces
    end
end

# =============================================================================
# Test functions
# =============================================================================

function run_earth_tests()
    @testset "build_gcd_bundle" begin
        test_build_gcd_bundle_structure()
        test_build_gcd_bundle_stores_raw_arrays()
        test_build_gcd_bundle_jld2_roundtrip()
    end

    @testset "make_watertight" begin
        test_make_watertight_already_closed()
        test_make_watertight_open_mesh()
    end

    @testset "dump_to_h5" begin
        test_dump_to_h5_schema()
        test_dump_to_h5_values()
    end

    @testset "dump_to_ply" begin
        test_dump_to_ply_g_frame()
        test_dump_to_ply_g_frame_max_radius()
        test_dump_to_ply_g_frame_binary_roundtrip()
        test_dump_to_ply_g_frame_watertight_depth()
        test_dump_to_ply_d_frame()
        test_dump_to_ply_d_frame_binary_roundtrip()
        test_dump_to_ply_bad_stream()
    end
end

# -----------------------------------------------------------------------------
# build_gcd_bundle
# -----------------------------------------------------------------------------

function test_build_gcd_bundle_structure()
    frames = _test_bundle()

    @test frames isa TamboFrames
    @test length(frames.g_frames) == 1
    @test length(frames.c_frames) == 1
    @test length(frames.d_frames) == 1

    g = frames.g_frames[end]
    d = frames.d_frames[end]

    for key in ("prem", "topography", "bvh", "cs", "geometry_hash",
                "vertices", "faces", "longlat_rad", "prem_radii")
        @test haskey(g, key)
    end
    @test haskey(d, "detector_region")
    @test haskey(d, "detector_bvh")
end

function test_build_gcd_bundle_stores_raw_arrays()
    verts, faces, det = _test_mesh()
    frames = build_gcd_bundle(verts, faces, _TEST_LONGLAT, _TEST_PREM_RADII, det)
    g = frames.g_frames[end]
    d = frames.d_frames[end]

    @test g["vertices"]     == verts
    @test g["faces"]        == faces
    @test g["longlat_rad"]  ≈ collect(_TEST_LONGLAT)
    @test d["detector_region"] == det
    @test length(g["prem"]) == length(_TEST_PREM_RADII)
    @test length(g["topography"]) == size(faces, 1)
end

function test_build_gcd_bundle_jld2_roundtrip()
    frames = _test_bundle()
    path   = tempname() * ".jld2"
    try
        save_frames(path, frames, streams=('G', 'C', 'D'))
        loaded = load_frames(path)
        g = loaded.g_frames[end]
        d = loaded.d_frames[end]

        for key in ("vertices", "faces", "longlat_rad", "prem_radii", "geometry_hash")
            @test haskey(g, key)
        end
        @test haskey(d, "detector_region")

        orig_g = frames.g_frames[end]
        @test g["geometry_hash"] == orig_g["geometry_hash"]
    finally
        isfile(path) && rm(path)
    end
end

# -----------------------------------------------------------------------------
# make_watertight
# -----------------------------------------------------------------------------

function test_make_watertight_already_closed()
    # Closed tetrahedron — four faces, no boundary edges.
    verts = Float64[1 0 0; 0 1 0; 0 0 1; 0 0 0]
    faces = Int[1 2 3; 1 2 4; 1 3 4; 2 3 4]
    @test _boundary_edge_count(faces) == 0

    new_verts, new_faces = make_watertight(verts, faces)
    @test new_verts === verts
    @test new_faces === faces
end

function test_make_watertight_open_mesh()
    # Single open triangle — all three edges are boundary edges.
    verts = Float64[1 0 0; 0 1 0; 0 0 1]
    faces = Int[1 2 3]
    @test _boundary_edge_count(faces) == 3

    new_verts, new_faces = make_watertight(verts, faces; depth_m=0.1)
    @test _boundary_edge_count(new_faces) == 0
    @test size(new_verts, 1) > size(verts, 1)
    @test size(new_faces, 1) > size(faces, 1)
end

# -----------------------------------------------------------------------------
# dump_to_h5
# -----------------------------------------------------------------------------

function test_dump_to_h5_schema()
    frames  = _test_bundle()
    g_frame = frames.g_frames[end]
    d_frame = frames.d_frames[end]
    path    = tempname() * ".h5"
    try
        dump_to_h5(g_frame, d_frame, path, "test_group")
        h5open(path) do f
            @test haskey(f, "test_group")
            grp = f["test_group"]
            for key in ("location", "radii", "vertices", "faces", "detector1")
                @test haskey(grp, key)
            end
            loc = read(grp["location"])
            @test length(loc) == 2
            @test isapprox(loc[1], rad2deg(_TEST_LONGLAT[1]), atol=1e-10)
            @test isapprox(loc[2], rad2deg(_TEST_LONGLAT[2]), atol=1e-10)
        end
    finally
        isfile(path) && rm(path)
    end
end

function test_dump_to_h5_values()
    verts, faces, det = _test_mesh()
    frames  = build_gcd_bundle(verts, faces, _TEST_LONGLAT, _TEST_PREM_RADII, det)
    g_frame = frames.g_frames[end]
    d_frame = frames.d_frames[end]
    path    = tempname() * ".h5"
    try
        dump_to_h5(g_frame, d_frame, path, "site")
        h5open(path) do f
            grp = f["site"]
            @test read(grp["vertices"])   == verts
            @test read(grp["faces"])      == faces
            @test read(grp["detector1"])  == det
            @test length(read(grp["radii"])) == length(_TEST_PREM_RADII)
        end
    finally
        isfile(path) && rm(path)
    end
end

# -----------------------------------------------------------------------------
# dump_to_ply
# -----------------------------------------------------------------------------

function test_dump_to_ply_g_frame()
    frames  = _test_bundle()
    g_frame = frames.g_frames[end]
    path    = tempname() * ".ply"
    try
        dump_to_ply(g_frame, path)
        @test isfile(path)
        @test filesize(path) > 0
        header = _read_ply_header(path)
        @test header[1] == "ply"
        @test any(l -> occursin("binary_little_endian", l), header)
        @test _ply_vertex_count(header) == size(g_frame["vertices"], 1)
        @test _ply_face_count(header)   == size(g_frame["faces"], 1)
    finally
        isfile(path) && rm(path)
    end
end

function test_dump_to_ply_g_frame_max_radius()
    frames  = _test_bundle()
    g_frame = frames.g_frames[end]
    path_full    = tempname() * ".ply"
    path_cropped = tempname() * ".ply"
    try
        dump_to_ply(g_frame, path_full)
        dump_to_ply(g_frame, path_cropped; max_radius_km=0.001)  # 1 m — crops nearly all faces
        n_full    = _ply_face_count(_read_ply_header(path_full))
        n_cropped = _ply_face_count(_read_ply_header(path_cropped))
        @test n_cropped < n_full
    finally
        isfile(path_full)    && rm(path_full)
        isfile(path_cropped) && rm(path_cropped)
    end
end

function test_dump_to_ply_g_frame_binary_roundtrip()
    # Parses the binary payload back and asserts vertex coordinates round-trip
    # exactly and face indices are written 0-based.
    frames  = _test_bundle()
    g_frame = frames.g_frames[end]
    path    = tempname() * ".ply"
    try
        dump_to_ply(g_frame, path)
        verts_out, faces_out = _parse_binary_ply(path)
        @test verts_out == g_frame["vertices"]
        @test Int.(faces_out) == g_frame["faces"] .- 1
    finally
        isfile(path) && rm(path)
    end
end

function test_dump_to_ply_g_frame_watertight_depth()
    # Open mesh (`_test_mesh` is a flat square — has a boundary loop). Verify
    # that `watertight_depth` actually closes the dumped PLY and adds vertices.
    frames  = _test_bundle()
    g_frame = frames.g_frames[end]
    p_open    = tempname() * ".ply"
    p_closed  = tempname() * ".ply"
    try
        dump_to_ply(g_frame, p_open)
        dump_to_ply(g_frame, p_closed; watertight_depth=10_000.0)
        verts_o, faces_o = _parse_binary_ply(p_open)
        verts_c, faces_c = _parse_binary_ply(p_closed)
        @test _boundary_edge_count(Int.(faces_o) .+ 1) > 0
        @test _boundary_edge_count(Int.(faces_c) .+ 1) == 0
        @test size(verts_c, 1) > size(verts_o, 1)
        @test size(faces_c, 1) > size(faces_o, 1)
    finally
        isfile(p_open)   && rm(p_open)
        isfile(p_closed) && rm(p_closed)
    end
end

function test_dump_to_ply_d_frame()
    verts, faces, det = _test_mesh()
    frames  = build_gcd_bundle(verts, faces, _TEST_LONGLAT, _TEST_PREM_RADII, det)
    d_frame = frames.d_frames[end]
    path    = tempname() * ".ply"
    try
        dump_to_ply(d_frame, path)
        @test isfile(path)
        header = _read_ply_header(path)
        @test header[1] == "ply"
        @test _ply_face_count(header) == length(det)
        @test _ply_face_count(header) < size(faces, 1)
    finally
        isfile(path) && rm(path)
    end
end

function test_dump_to_ply_d_frame_binary_roundtrip()
    # Verify the D-frame binary payload matches `_detector_subset_vf` output.
    verts, faces, det = _test_mesh()
    frames  = build_gcd_bundle(verts, faces, _TEST_LONGLAT, _TEST_PREM_RADII, det)
    d_frame = frames.d_frames[end]
    path    = tempname() * ".ply"
    expected_verts, expected_faces =
        TamboSim._detector_subset_vf(verts, faces, det)
    try
        dump_to_ply(d_frame, path)
        verts_out, faces_out = _parse_binary_ply(path)
        @test verts_out == expected_verts
        @test Int.(faces_out) == expected_faces .- 1
    finally
        isfile(path) && rm(path)
    end
end

function test_dump_to_ply_bad_stream()
    m_frame = Frame('M', Dict{String,Any}())
    @test_throws ErrorException dump_to_ply(m_frame, tempname() * ".ply")
end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Earth" begin
        run_earth_tests()
    end
end
