"""
    ScalarBatchAccumulator(net, state, batch_size)

A ScalarBatchAccumulator is used to evaluate the contribution to
local observables ⟨σ|Ô|σ'⟩ψ(σ')/ψ(σ) , but by computing the neural
network ψ(σ) in batches of size `batch_size`. This is essential
to extrract a speedup when using GPUs.

This is an internal implementation detail of NeuralQuantum, and should
not be relied upon.

Once constructed, a ScalarBatchAccumulator is supposed to be used as follows:
- if `isfull(sba) == true` you should not push new elements to it (an error
will be throw otherwise)
- data is pushed as `sba(⟨σ|Ô|σ'⟩, σ', ψ(σ))`.
The configuration should be passed as a vector (if ket) or as a tuple
of two vectors (if density matrix).
"""
mutable struct ScalarBatchAccumulator{N,A,B,C,D}
    bnet::N         # A batched version of the cached neural network

    in_buf::A       # the matrix of Nsites x batchsz used as input
    out_buf::B      # The row vector of outputs

    ψ0_buf::C       # Buffers alls the <σ|ψ> of the denominator
    mel_buf::D      # ⟨σ|Ô|σ'⟩ in the buffer

    buf_n::Int      # Counter for elements in buffer
    batch_sz::Int   # batch size
end

function ScalarBatchAccumulator(net::NeuralNetwork, v::State, batch_sz)
    bnet    = cached(net, batch_sz)

    w       = trainable_first(net)
    RT      = real(eltype(w))
    in_buf  = preallocate_state_batch(w, RT, v, batch_sz)
    out_buf = similar(w, out_type(net), 1, batch_sz)

    ψ0_buf  = similar(w, out_type(net), 1, batch_sz)
    mel_buf = similar(w, out_type(net), 1, batch_sz)

    return ScalarBatchAccumulator(
        bnet, in_buf, out_buf,
        ψ0_buf, mel_buf, 0, batch_sz)
end


Base.length(a::ScalarBatchAccumulator) = a.batch_sz
Base.count(a::ScalarBatchAccumulator)  = a.buf_n
isfull(a::ScalarBatchAccumulator) = count(a) == length(a)

"""
    init!(c::ScalarBatchAccumulator)

Resets the internal counter of the accumulator, deleting
all previously accumulated (but not computed) values.
"""
init!(c::ScalarBatchAccumulator) = c.buf_n = 0

function (c::ScalarBatchAccumulator)(mel, v, ψ0)
    @assert !isfull(c) "Pushed data to a full accumulator."

    # Increase the step in our internal buffer
    # this should be guaranteed to always be < max_capacity
    c.buf_n = c.buf_n + 1

    c.ψ0_buf[c.buf_n]   = ψ0
    c.mel_buf[c.buf_n]  = mel
    store_state!(c.in_buf, v, c.buf_n)
end

"""
    process_accumulator!(c)

Processes all states stored in the accumulator, by computing their
relative local contribution.

It is safe to call this even if the accumulator is not full. In this
case all data beyond the count should be disregarded as it was
not initialized.

The output will be returned. You should not assume ownership of
the output, as it is preallocated and will be used for further
computations of the accumulator.
"""
function process_accumulator!(c::ScalarBatchAccumulator)
    out_buf  = logψ!(c.out_buf, c.bnet, c.in_buf)
    out_buf .-= c.ψ0_buf
    out_buf  .= exp.(out_buf)
    #collect ? if using the gpu... need to think about this

    out_buf .*= c.mel_buf
    init!(c)
    
    return out_buf
end