"""
    KLocalOperator

A representation of a local operator, acting on certain `sites`, each with
`hilb_dims` dimension. The local operator is written in matrix form in this
basis as `mat`. For every row of `mat` there are several non-zero values contained
in `mel`, and to each of those, `to_change` contains the sites that must change the basis
new value, contained in `new_value`
"""
struct KLocalOperator{SV,M,Vel,Vtc,Vtv} <: AbsLinearOperator
    # list of sites on which this operator acts
    sites::SV

    # local hilbert space dimensions for each site
    hilb_dims::SV

    # Operator (as a matrix) represented
    mat::M

    # Matrix elements, per row
    mel::Vector{Vel}

    # List of indices that should be changed
    to_change::Vector{Vtc}

    # List of values of that should be changed
    new_values::Vector{Vtv}
end

"""
    KLocalOperatorRow(sites::Vector, hilb_dims::Vector, operator)

Creates a KLocalOperator where connections are stored by row for the operator
    `operator` acting on `sites` each with `hilb_dims` local dimension.
"""
function KLocalOperatorRow(sites::Vector, hilb_dims::Vector, operator)
    # TODO Generalize to arbistrary spaces and not only uniform
    st = NAryState(eltype(operator), first(hilb_dims), length(sites))
    st1 = NAryState(eltype(operator), first(hilb_dims), length(sites))
    mel        = Vector{Vector{eltype(operator)}}()
    to_change  = Vector{Vector{Vector{eltype(Int)}}}()
    new_values = Vector{Vector{Vector{eltype(operator)}}}()

    for (r, row) = enumerate(eachrow(operator))
        mel_els = [row[r]]
        to_change_els  = [Int[]]
        new_values_els = [eltype(mel_els)[]]

        set!(st, r)
        for (c, val) = enumerate(row)
            r == c && continue
            abs(val) < 10e-6 && continue

            set!(st1, c)
            cngd = Int[]
            nwvls = eltype(mel_els)[]
            for (i, (v, vn)) = enumerate(zip(config(st), config(st1)))
                if v != vn
                    push!(cngd, i)
                    push!(nwvls, vn[i])
                end
            end
            push!(mel_els, val)
            push!(to_change_els, cngd)
            push!(new_values_els, nwvls)
        end

        push!(mel, mel_els)
        push!(to_change, to_change_els)
        push!(new_values, new_values_els)
    end
    KLocalOperator(sites, hilb_dims, operator |> collect, mel, to_change, new_values)
end

## Accessors
sites(op::KLocalOperator) = op.sites

conn_type(top::Type{KLocalOperator{SV,M,Vel,Vtc,Vtv}}) where {SV, M, Vel, Vtc, Vtv} =
    OpConnection{Vel, Vtc, Vtv}
conn_type(op::KLocalOperator{SV,M,Vel,Vtc,Vtv}) where {SV, M, Vel, Vtc, Vtv} =
    OpConnection{Vel, Vtc, Vtv}

# Copy
function duplicate(op::KLocalOperator)
    KLocalOperator(deepcopy(op.sites), deepcopy(op.hilb_dims), deepcopy(op.mat),
                    deepcopy(op.mel), deepcopy(op.to_change),
                    deepcopy(op.new_values))
end

##
function row_valdiff!(conn::OpConnection, op::KLocalOperator, v::State)
    # Find row index
    r = local_index(v, sites(op))

    # Return values
    mel = op.mel[r]
    tc  = op.to_change[r]
    nv  = op.new_values[r]

    append!(conn, (mel, tc, nv))
end

# sum
function sum_samesite!(op_l::KLocalOperator, op_r::KLocalOperator)
    @assert op_l.sites == op_r.sites
    @assert length(op_l.mel) == length(op_r.mel)

    op_l.mat .+= op_r.mat

    n = length(op_l.mel)
    for (i, (mel_vals_l, mel_vals_r)) = enumerate(zip(op_l.mel, op_r.mel))

        for (mel, tch, nv) = zip(op_r.mel[i], op_r.to_change[i], op_r.new_values[i])
            ids_tch = findall(isequal(tch), op_l.to_change[i])
            found = 0
            for id=ids_tch
                if op_l.new_values[i][id] == nv
                    found = id
                    break
                end
            end

            if found == 0
                push!(op_l.mel[i], mel)
                push!(op_l.to_change[i], tch)
                push!(op_l.new_values[i], tch)
            else
                op_l.mel[i][found] += mel
            end
        end
    end
    op_l
end

sum_samesite(op_l::KLocalOperator, op_r::KLocalOperator) = sum_samesite!(duplicate(op_l), op_r)

Base.transpose(op::KLocalOperator) = KLocalOperatorRow(deepcopy(op.sites),
                                                       deepcopy(op.hilb_dims),
                                                       transpose(op.mat)|>collect)

function Base.conj!(op::KLocalOperator)
    conj!(op.mat)
    for el=op.mel
        conj!.(el)
    end
    op
end

Base.conj(op::KLocalOperator) = conj!(duplicate(op))

Base.adjoint(op::KLocalOperator) = conj(tranpose(op))
