struct CorsikaEvent{T<:Real}
    particle::Particle{T}
    time::Quantity{T, tdim, typeof(u"s")}
    weight::T
end

#function read_corsika(
#    particles_file::String,
#    config_file::String,
#    cs_earth::CoordinateSystem{T},
#    filter_fxn::Function=x->true
#) where {T<:Real}
#
#    config = open(config_file) do file
#        YAML.load(file)
#    end
#
#    r = AngleAxis(-π/2, cs_earth.origin...)
#    cs_corsika = CoordinateSystem(
#        cs_earth.origin,
#        Float64.(cs_earth.rotation*r)
#    )
#
#    rot = RotMatrix(SMatrix{3, 3, T, 9}([
#        config["x-axis"]...;
#        config["y-axis"]...;
#        config["plane"]["normal"]
#    ]))
#    center = config["plane"]["center"] .* u"m"
#
#    dset = Parquet2.Dataset(particles_file)
#    rows = Tables.rows(dset)
#    events = CorsikaEvent{T}[]
#    for row in rows
#        particle = Particle(row, rot, config["plane"]["center"], cs_corsika, cs_earth)
#        if ~filter_fxn(particle)
#            continue
#        end
#        event = CorsikaEvent(particle, T(row.time * u"s"), T(row.weight))
#        push!(events, event)
#    end
#    return events
#end

function read_corsika(
    basedir::String,
    cs_earth::CoordinateSystem{T},
    filter_fxn::Function=x->true
) where {T<:Real}
    dirs = glob("shower_*/particles/", basedir)
    filenames, transforms = String[], Function[]

    for dir in dirs
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
        trans(row) = CorsikaEvent(row, rot, center, cs_corsika, cs_earth)
        push!(filenames, particles_file)
        push!(transforms, trans)
    end
    return MultiParquetIterator(filenames, transforms[1];T=CorsikaEvent)
end

function CorsikaEvent(
    row,
    rot::V,
    center,
    cs_corsika::CoordinateSystem{U},
    cs_earth::CoordinateSystem{U},
) where {U<:Real, V<:Rotation}
    d = Direction(rot * [row.nx, row.ny, row.nz], cs_corsika)
    p = Coordinate((rot * [row.x, row.y, row.z] .* u"m" .+ center)  .- [0.0u"km", 0.0u"km", 6371.0u"km"], cs_corsika)
    e = U(row.kinetic_energy * u"GeV")
    pdg = Int64(row.pdg)
    particle = Particle(pdg, e, convert(cs_earth, p), convert(cs_earth, d))
    return CorsikaEvent(particle, Float64(row.time*u"s"), Float64(row.weight))

end
