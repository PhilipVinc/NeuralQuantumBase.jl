export sum_autobatch

"""
    sum_autobatch(v)

it's equivalent to `sum(v, dims=1)` except for the case of a vector, where it
will return a scalar instead of a 1-element vector.
"""
sum_autobatch(v) = sum(v, dims=1)
sum_autobatch(v::AbstractVector) = sum(v)

"""
    _batched_outer_prod!(R, vb, wb)

Efficiently performs the outer product R[i] .= vb[i] .* wb[i]'
along the batch dimension i, assuming that the batch dimension
is the last.

R[i] is a matrix, vb[i] and wb[i] are vectors.

Internally uses the fact that R is a StridedView.
"""
@inline function _batched_outer_prod!(R::StridedView, vb, wb)
    @inbounds for i=1:size(R, 3)
        @inbounds for j=1:size(wb, 1)
            @simd for k= @inbounds 1:size(vb, 1)
                @inbounds R[k,j,i] = vb[k,i]*conj(wb[j,i])
            end
        end
    end
    return R
end

@inline function _batched_outer_prod_noconj!(R::StridedView, vb, wb)
    @inbounds for i=1:size(R, 3)
        @inbounds for j=1:size(wb, 1)
            @simd for k= @inbounds 1:size(vb, 1)
                @inbounds R[k,j,i] = vb[k,i]*wb[j,i]
            end
        end
    end
    return R
end


@inline function _batched_outer_prod!(R::StridedView, α, vb, wb)
    @inbounds for i=1:size(R, 3)
        @inbounds for j=1:size(wb, 1)
            @simd for k= @inbounds 1:size(vb, 1)
                @inbounds R[k,j,i] = α * vb[k,i]*conj(wb[j,i])
            end
        end
    end
    return R
end

@inline function _batched_outer_prod_∑!(R::StridedView, α, vb, wb, vb2, wb2)
    @inbounds for i=1:size(R, 3)
        @inbounds for j=1:size(wb, 1)
            @simd for k= @inbounds 1:size(vb, 1)
                @inbounds R[k,j,i] = α * (vb[k,i]*conj(wb[j,i]) + vb2[k,i]*conj(wb2[j,i]))
            end
        end
    end
    return R
end

@inline function _batched_outer_prod_Δ!(R::StridedView, α, vb, wb, vb2, wb2)
    @inbounds for i=1:size(R, 3)
        @inbounds for j=1:size(wb, 1)
            @simd for k= @inbounds 1:size(vb, 1)
                @inbounds R[k,j,i] = α * (vb[k,i]*conj(wb[j,i]) - vb2[k,i]*conj(wb2[j,i]))
            end
        end
    end
    return R
end
