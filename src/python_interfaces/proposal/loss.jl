struct StochasticLoss{T}
    int_type::Int
    energy::Quantity{T,edim,typeof(u"GeV")}
    position::Coordinate{T}
    function StochasticLoss(
        int_type::Int,
        energy::Q,
        position::Coordinate{T}
    ) where {T<:Real,Q<:Quantity{T,edim}}
        energy = energy |> u"GeV"
        return new{T}(int_type, energy, position)
    end
end

#function Loss(
#    int_type::Int,
#    e::Quantity{T,edim,typeof(u"GeV")},
#    pp_position::PyObject
#) where {T<:Real}
#    position = position_from_pp_vector(pp_position)
#    return Loss{T}(int_type, e, position)
#end
