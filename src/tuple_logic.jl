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
function weight_tuple(obj, vec=similar(trainable_first(obj), 0),
                      start=1)
    x = trainable(obj)
    i = 0
    if x isa Tuple
        d=Vector()
        for f=propertynames(x)
            di, val = weight_tuple(getproperty(x,f), vec, start+i)
            i += di; push!(d, val)
        end
        i, Tuple(d)
    else
        d=Dict{Symbol, Any}()
        for f=propertynames(x)
            di, val = weight_tuple(getproperty(x,f), vec, start+i)
            i += di; push!(d, f=>val)
        end
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
    if size(x) == size(data_vec)
        reshpd_params = data_vec
    else
        reshpd_params = reshape(data_vec, size(x))
    end
    return length(x), reshpd_params
end

## For Batches
function batched_weight_tuple(grad_tup, bsz=1)
    @info "useless"
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
    if size(data_vec) != (size(x)..., bsz)
        reshpd_params = reshape(data_vec, size(x)..., bsz)
        if x isa Array
            reshpd_params = StridedView(reshpd_params)
        end
    else
        reshpd_params = data_vec
    end
    return length(x), reshpd_params
end # ? stridedView?


"""
    apply_recurse!(out::tuple, orig::Zygote.Grads, weights, op=identity)

recurses into all fields of `out`, which is assumed to have the structure
generated by `trainable(weights)`. When it hits abstractarrays, it copies
the corresponding field `orig[weights[key]]` to `out[key]`, by applying the
elementwise unary operation `op`.

This convoluted way is because zygote returns gradient results that do not respect
the trainable interface, and we need to reconstruct it.
"""
function apply_recurse!(out, orig, weights, op=identity)
    weights = trainable(weights)
    for key=keys(out)
        apply_recurse!(out[key], orig, weights[key], op)
    end
    return out
end

apply_recurse!(out::AbstractArray, orig, weight::AbstractArray, op) =
    op(copyto!(out, orig[weight]))

"""
    accum_recurse!(out::tuple, orig::Zygote.Grads, weights, op=identity; init=true)

Similar to `apply_recurse!`, but accumulates and only sets the out to 0 if
`init==true`.
"""
function accum_recurse!(out, orig, weights, op=identity; init=true)
    weights = trainable(weights)
    for key=keys(out)
        accum_recurse!(out[key], orig, weights[key], op; init=init)
    end
    return out
end

function accum_recurse!(out::AbstractArray, orig, weight::AbstractArray, op; init=true)
    if init
        out .= 0
    end

    if length(size(out)) == 1 && length(size(orig[weight])) == 2
        out .+= op.(view(orig[weight],:))
    else
        out .+= op.(orig[weight])
    end
end
