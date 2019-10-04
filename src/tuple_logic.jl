export weight_tuple

"""
    trainable_first(net)

Returns the first array in trainable(net), by recursively applying first to it.
"""
trainable_first(net) = trainable_first(first(trainable(net)))
trainable_first(x::AbstractArray)   = x

"""
    trainable_length

"""
trainable_length(net::NeuralNetwork) = _tlen(net)
function _tlen(t)
    i = 0
    for el=trainable(t)
        i+=_tlen(el)
    end
    return i
end
_tlen(t::AbstractArray) = length(t)

"""
    weight_tuple(net)

Returns a named tuple holding all the fields in the network, and an
extra field named `tuple_all_weights` who has the same type
"""
weight_tuple(cnet::CachedNet) = weight_tuple(cnet.net)
weight_tuple(net::NeuralNetwork) = weight_tuple(net)[2]
function weight_tuple(obj, vec=similar(trainable_first(x), 0),
                      start=1)
    x = trainable(obj)
    i = 0
    if x isa Tuple
        d=Vector()
        for f=propertynames(x)
            di, val = weight_tuple(getfield(x,f), vec, start+i)
            i += di; push!(d, val)
        end
        #start == 1 && push!(d, :tuple_all_weights=>[vec])
        i, Tuple(d)
    else
        d=Dict{Symbol, Any}()
        for f=propertynames(x)
            di, val = weight_tuple(getfield(x,f), vec, start+i)
            i += di; push!(d, f=>val)
        end
        #start == 1 && push!(d, :tuple_all_weights=>[vec])
        i, (;d...)
    end
end

function weight_tuple(obj::Tuple, vec::AbstractVector, start)
    x = trainable(obj)
    i = 0
    d=Vector()
    for f=propertynames(x)
        di, val = weight_tuple(getfield(x,f), vec, start+i)
        i += di; push!(d, val)
    end
    i, Tuple(d)
end

function weight_tuple(x::AbstractArray{<:Number}, vec::AbstractVector, start)
    length(vec) < start+length(x)-1 && resize!(vec, start+length(x)-1)
    @views data_vec = vec[start:start+length(x)-1]
    reshpd_params = reshape(data_vec, size(x))
    reshpd_params .= x
    return length(x), reshpd_params
end

## For Batches
function batched_weight_tuple(grad_tup, bsz=1)
    all_weights = grad_tup.tuple_all_weights
    all_weghts_new = [similar(w, length(w), bsz) for w=all_weights][1]
    return batched_weight_tuple(grad_tup, all_weghts_new)[2]
end

function batched_weight_tuple(obj, vec::AbstractMatrix, start=1)
    x = trainable(obj)
    i = 0
    if x isa Tuple
        d=Vector()
        for f=propertynames(x)
            f==:tuple_all_weights && continue
            di, val = batched_weight_tuple(getfield(x,f), vec, start+i)
            i += di; push!(d, val)
        end
        i, Tuple(d)
    else
        d=Dict{Symbol, Any}()
        for f=propertynames(x)
            f==:tuple_all_weights && continue
            di, val = batched_weight_tuple(getfield(x,f), vec, start+i)
            i += di; push!(d, f=>val)
        end
        i, (;d...)
    end
end

function batched_weight_tuple(x::AbstractArray{<:Number}, vec::AbstractMatrix, start)
    @assert length(vec) >= start+length(x)-1
    bsz = size(vec, 2)

    @views data_vec = vec[start:start+length(x)-1, :]
    reshpd_params = reshape(data_vec, size(x)..., bsz)
    reshpd_params .= x
    if reshpd_params isa Base.ReshapedArray
        reshpd_params = StridedView(reshpd_params)
    end
    return length(x), reshpd_params
end # ? stridedView?

#
"""
    conjcopy_leaves!(out, in)

Recursively maps all fields of `in`, conjugating them and copying to the respective
field of `out`.
"""
conjcopy_leaves!(out, in::Union{Tuple,NamedTuple}) = begin
    for key=keys(in)
        conjcopy_leaves!(out[key], in[key])
    end
    return out
end

conjcopy_leaves!(out::AbstractArray, in::AbstractArray) = copyto!(out, conj!(in))
