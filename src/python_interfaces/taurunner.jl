using PyCall

const tr = PyNULL()
const earth = PyNULL()
const sphere_clp = PyNULL()
const SlabClp = PyNULL()
const xs = PyNULL()
const Chord = PyNULL()
const SlabTrack = PyNULL()
const tr_media = PyNULL()
const StandardRock = PyNULL()
const Air = PyNULL()

function tr_init()
    copy!(tr, pyimport("taurunner"))
    x = tr.body.earth
    copy!(earth, x.construct_earth([(1, 2.6)])) # 3km or rock gets us to sea level and 1km is reasonable for TAMBO location
    copy!(xs, tr.cross_sections.CrossSections(tr.cross_sections.XSModel.CSMS))
    copy!(sphere_clp, tr.proposal_interface.ChargedLeptonPropagatorSphere(earth))
    copy!(SlabClp, tr.proposal_interface.ChargedLeptonPropagatorSlab)
    copy!(Chord, tr.track.chord)
    copy!(SlabTrack, tr.track.SlabTrack)
    copy!(tr_media, tr.body.layered_constant_slab.Media)
    copy!(StandardRock, tr.body.layered_constant_slab.Media.StandardRock)
    copy!(Air, tr.body.layered_constant_slab.Media.Air)
    ## Voodoo. Please don't touch
    #try
    #    copy!(prop_cache, PyDict())
    #catch e
    #    global prop_cache = PyDict()
    #end


    py"""
    import taurunner as tr
    from taurunner.utils import units
    import numpy as np
    def stopping_condition(p, body, track):
        if abs(p.ID==15):
            c = 299_792_458 * units.meter / units.sec
            tautau = 2.903e-13 * units.sec
            lrange = -p.energy / (1.776 * units.GeV) * c * tautau * np.log(1e-3)
            d = lrange / body.length
            remaining_distance = track.x_to_d(1-p.position)
            return d > remaining_distance
        elif abs(p.ID) in [12, 14, 16]:
            remaining_depth = track.total_column_depth(body) - track.x_to_X(body, p.position)
            depth_step = p.GetTotalInteractionDepth()
            return depth_step * 1e-3 > remaining_depth
        return True
    prop_cache = {}
    """
end

function taurunner_interface(
    particle::Particle{T},
    intersections::I,
)::Particle{T} where {T<:Real,I<:AbstractVector{Intersection{T}}}

    tr_particle = tr.particle.Particle(
        particle.pdg_id,
        ustrip(particle.energy |> u"eV"),
        0.0,
        xs
    )
    if should_go_through_earth(intersections)
        theta, _ = cart_to_sph(particle.direction)
        track = Chord(theta=theta)
        out_tr_particle = tr.Propagate(
            tr_particle,
            track,
            earth,
            sphere_clp,
            condition=py"stopping_condition"
        )
        distance = (track.x_to_d(1)-track.x_to_d(out_tr_particle.position)) * earth.length / tr.utils.units.meter * u"m"
        position = distance * reverse(particle.direction) + particle.position
        pdg_id = convert(Int, out_tr_particle.ID)
        energy = out_tr_particle.energy / tr.utils.units.GeV * u"GeV"
        return Particle(pdg_id, energy, position, particle.direction)
    else
        intersections = cull_intersections(intersections)

        total_distance = last(intersections).distance
        densities, boundaries, media = Float64[], [], String[]
        itr = Iterators.rest(reverse(intersections), 2)
        for intersection in Iterators.rest(reverse(intersections), 2)
            is_rock = dot(particle.direction, intersection.normal) > 0 || typeof(intersection)==Tambo.SphereIntersection{T}
            push!(boundaries, ustrip(total_distance - intersection.distance))
            push!(densities, is_rock ? 2.6 : 1.2e-3)
            push!(media, is_rock ? "StandardRock" : "Air")
        end
        if last(media)=="Air"
            push!(media, "StandardRock")
            push!(densities, 2.6)
            push!(boundaries, ustrip(total_distance))
        end
        boundaries ./= last(boundaries)
        track = SlabTrack()
        body = tr.body.LayeredConstantSlab(
            densities,
            media,
            ustrip(last(intersections).distance |> u"km"),
            boundaries
        )
        slab_clp = SlabClp(body)

        slab_clp._propagators = PyDict(prop_cache)

        out_tr_particle = tr.Propagate(
            tr_particle,
            track,
            body,
            slab_clp,
            condition=py"stopping_condition"
        )
        distance = track.x_to_d(out_tr_particle.position) * body.length / tr.utils.units.meter * u"m"
        position = distance * particle.direction + last(intersections).point
        pdg_id = out_tr_particle.ID
        energy = out_tr_particle.energy / tr.utils.units.GeV * u"GeV"
        return Particle(pdg_id, energy, position, particle.direction)
    end
end

function cull_intersections(
    intersections::I,
)::Vector{Intersection{T}} where {T<:Real,I<:AbstractVector{Intersection{T}}}
    include_triangles = true
    culled_intersections = Intersection{T}[]
    for intersection in intersections
        if typeof(intersection)==SphereIntersection{T}
            push!(culled_intersections, intersection)
            include_triangles = false
        elseif include_triangles
            push!(culled_intersections, intersection)
        end
    end
    return culled_intersections
end

function should_go_through_earth(
    intersections::I
)::Bool where {T<:Real,I<:AbstractVector{Intersection{T}}}
    sphere_counter = 0
    for intersection in intersections
        if typeof(intersection)==SphereIntersection{T}
            sphere_counter += 1
        end
    end
    return sphere_counter > 4
end
