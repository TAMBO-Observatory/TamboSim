mutable struct MultiParquetIterator{T}
    filenames::Vector{String}
    current_file_idx::Int
    current_table::Union{Nothing, Any}
    current_row_iterator::Union{Nothing, Any}
    transform::Function
    chunk_size::Int
    T::Type{T}
    records_buffer::Vector{T}
    iter_state::Union{Nothing, Int}
end


function Base.iterate(iter::MultiParquetIterator, state=nothing)
    # Fill buffer if empty
    if isempty(iter.records_buffer)
        if !fill_buffer!(iter)
            return nothing
        end
    end

    # Pop from buffer
    record = popfirst!(iter.records_buffer)
    return (record, nothing)
end

function fill_buffer!(iter::MultiParquetIterator)
    # Try to fill buffer with up to chunk_size records
    while length(iter.records_buffer) < iter.chunk_size
        # Get next row
        row = get_next_row(iter)
        if row === nothing
            # No more rows
            return !isempty(iter.records_buffer)
        end

        # Transform and add to buffer
        record = iter.transform(row)
        push!(iter.records_buffer, record)
    end

    return true
end

function get_next_row(iter::MultiParquetIterator)
    # If we have no current iterator, try to get one
    while iter.current_row_iterator === nothing
        # Check if we have more files
        if iter.current_file_idx > length(iter.filenames)
            return nothing
        end

        # Try to open next file
        filename = iter.filenames[iter.current_file_idx]
        try
            iter.current_table = Parquet2.readfile(filename)
            iter.current_row_iterator = Tables.rows(iter.current_table)
            iter.iter_state = 1
            iter.current_file_idx += 1
        catch e
            @warn "Failed to open file $filename: $e"
            iter.current_file_idx += 1
            # Continue to try next file
        end
    end

    try
        event, state = iterate(iter.current_row_iterator, iter.iter_state)
        iter.iter_state = state
        return event
    catch e
        # Iterator exhausted or error
        iter.current_row_iterator = nothing
        iter.current_table = nothing
        return get_next_row(iter)  # Try next file
    end
end

function Base.close(iter::MultiParquetIterator)
    # Cleanup if needed
    iter.current_table = nothing
    iter.current_row_iterator = nothing
    empty!(iter.records_buffer)
end

Base.IteratorSize(::Type{MultiParquetIterator}) = Base.SizeUnknown()
Base.eltype(::Type{MultiParquetIterator{T}}) where T = T

function MultiParquetIterator(filenames::Vector{String}, transform_func::Function;
        chunk_size::Int=1_000_000, T=CorsikaEvent)
    return MultiParquetIterator{T}(
        filenames, 1, nothing, nothing,
        transform_func, chunk_size, T,
        Vector{T}(), nothing
    )
end
