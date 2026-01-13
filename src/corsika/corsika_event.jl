struct CorsikaEvent{T<:Real}
    particle::Particle{T}
    weight::T
end

function read_corsika(
    basedir::String,
    cs_earth::CoordinateSystem{T},
    decaytime,
    filter_fxn::Function=x->true
) where {T<:Real}
    dirs = glob("shower_*/particles/", basedir)
    filenames, transforms = String[], Function[]

    for dir in dirs
        if ~isfile("$(dir)/summary.yaml")
            @warn "$(dir) did not finish running."
            continue
        end
        config_file = "$(dir)/config.yaml"
        particles_file = "$(dir)/particles.parquet"

        config = open(config_file) do file
            YAML.load(file)
        end
    
        r = AngleAxis(-π/2, cs_earth.origin...)
        cs_corsika = CoordinateSystem(
            cs_earth.origin,
            Float64.(cs_earth.rotation*r)
        )
    
        rot = RotMatrix(SMatrix{3, 3, T, 9}([
            config["x-axis"]...;
            config["y-axis"]...;
            config["plane"]["normal"]
        ]))
        center = config["plane"]["center"] .* u"m"
        trans(row) = CorsikaEvent(row, rot, center, decaytime, cs_corsika, cs_earth)
        push!(filenames, particles_file)
        push!(transforms, trans)
    end
    return MultiParquetIterator(filenames, transforms[1]; T=CorsikaEvent)
end

function CorsikaEvent(
    row,
    rot::V,
    center,
    decaytime,
    cs_corsika::CoordinateSystem{U},
    cs_earth::CoordinateSystem{U},
) where {U<:Real, V<:Rotation}
    d = Direction(rot * [row.nx, row.ny, row.nz], cs_corsika)
    p = Coordinate((rot * [row.x, row.y, row.z] .* u"m" .+ center)  .- [0.0u"km", 0.0u"km", 6371.0u"km"], cs_corsika)
    e = U(row.kinetic_energy * u"GeV")
    pdg = ParticleType(Int64(row.pdg))
    particle = Particle(pdg, e, convert(cs_earth, p), convert(cs_earth, d), decaytime+Float64(row.time*u"s"))
    return CorsikaEvent(particle, Float64(row.weight))
end
