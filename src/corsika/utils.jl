"""
    MultiParquetIterator{T}

An iterator for processing multiple Parquet files seamlessly.

This struct manages the state required to iterate through a list of Parquet files,
reading rows, applying a transformation function, and buffering the results. It is
designed to handle large datasets that are split across multiple files.

# Fields
- `filenames::Vector{String}`: A list of Parquet file paths to iterate over.
- `current_file_idx::Int`: The index of the current file being processed.
- `current_table`: The currently open Parquet table.
- `current_row_iterator`: The iterator for the rows of the current table.
- `transform::Function`: A function to apply to each row to transform it into the desired type `T`.
- `chunk_size::Int`: The number of records to buffer in memory.
- `T::Type{T}`: The element type that the iterator yields.
- `records_buffer::Vector{T}`: A buffer to hold the transformed records.
- `iter_state`: The state of the current row iterator.
"""
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


"""
    Base.iterate(iter::MultiParquetIterator, state=nothing)

Advances the iterator and returns the next element.

This is the core of the iteration protocol. It retrieves the next record from the
internal buffer. If the buffer is empty, it calls `fill_buffer!` to replenish it
from the Parquet files.

# Arguments
- `iter::MultiParquetIterator`: The iterator instance.
- `state`: The iteration state (unused, maintained for compatibility).

# Returns
- A tuple `(record, state)` if an element is available, otherwise `nothing`.
"""
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

"""
    fill_buffer!(iter::MultiParquetIterator) -> Bool

Replenishes the iterator's internal buffer.

This function reads rows from the current Parquet file, applies the transformation,
and adds records to the buffer until it reaches its `chunk_size`. It handles opening
new files and moving to the next one when the current one is exhausted.

# Arguments
- `iter::MultiParquetIterator`: The iterator instance.

# Returns
- `true` if the buffer was successfully filled (or partially filled if at the end of data),
  `false` if there are no more records to read.
"""
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

"""
    get_next_row(iter::MultiParquetIterator)

Retrieves the next raw row from the current Parquet file.

This is a helper function that manages the process of iterating through rows and
files. It handles opening the next file in the list when the current one is
exhausted and skips files that fail to open.

# Arguments
- `iter::MultiParquetIterator`: The iterator instance.

# Returns
- A table row object if successful, otherwise `nothing`.
"""
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

"""
    Base.close(iter::MultiParquetIterator)

Closes the iterator and releases resources.

This function cleans up the iterator by clearing the internal buffer and releasing
references to the open Parquet file and table, allowing for garbage collection.

# Arguments
- `iter::MultiParquetIterator`: The iterator instance to close.
"""
function Base.close(iter::MultiParquetIterator)
    # Cleanup if needed
    iter.current_table = nothing
    iter.current_row_iterator = nothing
    empty!(iter.records_buffer)
end

Base.IteratorSize(::Type{MultiParquetIterator}) = Base.SizeUnknown()
Base.eltype(::Type{MultiParquetIterator{T}}) where T = T

"""
    MultiParquetIterator(filenames::Vector{String}, transform_func::Function;
            chunk_size::Int=1_000_000, T=CorsikaEvent) -> MultiParquetIterator{T}

Constructs a `MultiParquetIterator`.

# Arguments
- `filenames::Vector{String}`: A list of Parquet file paths to iterate over.
- `transform_func::Function`: A function to apply to each row to transform it into the desired type `T`.
- `chunk_size::Int`: The number of records to buffer in memory. Defaults to 1,000,000.
- `T`: The element type that the iterator will yield. Defaults to `CorsikaEvent`.

# Returns
- A new `MultiParquetIterator` instance.
"""
function MultiParquetIterator(filenames::Vector{String}, transform_func::Function;
        chunk_size::Int=1_000_000, T=CorsikaEvent)
    return MultiParquetIterator{T}(
        filenames, 1, nothing, nothing,
        transform_func, chunk_size, T,
        Vector{T}(), nothing
    )
end
