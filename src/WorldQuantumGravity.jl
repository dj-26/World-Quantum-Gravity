module WorldQuantumGravity

using GraphPlot
using LightGraphs
using SparseArrays



# We can add comments like this
export Coord
struct Coord{D}
    c::NTuple{D,Int}
end

Base.getindex(c::Coord, i) = c.c[i]



#import listGridSize
#const listGridSize = (3,3,5)



export gridGraph
function gridGraph(listGridSize,m)
    sk = path_graph(listGridSize[length(listGridSize)])
    for i in length(listGridSize)-1:-1:1
       sk = cartesian_product(sk , path_graph(listGridSize[i]))
    end
    return sk
end



# grid object

export gridSize
function gridSize(listGridSize,j)
    prod(listGridSize[1:j])
end

export crd
function crd(listGridSize,m::Int)
    d = length(listGridSize)
    c = zeros(Int, d)
    m -= 1
    for i in 1:d
        c[i] = mod(m, listGridSize[i])
        m = fld(m, listGridSize[i])
    end
    @assert m == 0
    Coord(tuple(c...))
end

export lbl
function lbl(listGridSize,c::Coord{D}) where {D}
    m = 0
    for i in D:-1:1
        m = m * listGridSize[i] + c[i]
    end
    m + 1
end



export atom
function atom(listGridSize,c::Coord{D}) where {D}
    c1 = Coord{D}[]
    for offset in CartesianIndices(ntuple(i->2, D))
        push!(c1, Coord(ntuple(i -> c[i] + offset.I[i]-1, D)))
    end
    c1
end

function atom(listGridSize,m::Int)
# m is vertex label
    [lbl(listGridSize,c) for c in atom(listGridSize,crd(listGridSize,m))]
end



export Edgevv
"""refer to edge by (vertex, vertex)"""
struct Edgevv
    v1::Int
    v2::Int
end

export atomCorner

function atomCorner(listGridSize,m::Int, n::Int)
    # m labels atom by vertex label, n from 1 to 2^d enumerates vertex within atom
    d = length(listGridSize)
    crn = Edgevv[]
    for i in 1:2^d
        if sum(abs.([crd(listGridSize,atom(listGridSize,m)[n]).c...]-[crd(listGridSize,atom(listGridSize,m)[i]).c...]))==1
            push!(crn, Edgevv(atom(listGridSize,m)[n], atom(listGridSize,m)[i]))
        end
    end
    crn
end

function atomCorner(listGridSize,c::Coord{D}, n::Int) where {D}
    crn = Tuple{Coord{D},Coord{D}}[]
    for i in 1:2^D
        if sum(abs.([atom(listGridSize,c)[n].c...]-[atom(listGridSize,c)[i].c...]))==1
            push!(crn, (atom(listGridSize,c)[n], atom(listGridSize,c)[i]))
        end
    end
    crn
end



# amplitude

export vvmd
"""dspc = spatial dimension"""
#function vvmd(s,c,dspc)
#    if s == 0
#        return 1.0
#    else
#        return (sinc(s*sqrt(c/dspc)/pi))^(-dspc)
#    end
#end

## take in negative c
function vvmd(s,c,dspc)
    if s == 0
        return 1.0
    else
        return real((sinc(s*sqrt(Complex(c)/dspc)/pi))^(-dspc))
    end
end

export Edgevd
"""refer to edge by (vertex,direction)"""
struct Edgevd
    vert::Int
    dr::Int
end

export ampEdge
function ampEdge(listGridSize, svalue,cvalue,evd::Edgevd,L)
    dspc = length(listGridSize)-1
    m, dr = evd.vert, evd.dr
    if svalue[m,dr] == 0
        return 1
    else
        vd = vvmd(svalue[m,dr],cvalue[m,dr],dspc)+0im
        return vd^(3/vd)*exp(-L*svalue[m,dr]/vd)
    end
end

export direction
function direction(listGridSize, e::Edgevv)
    d = length(listGridSize)
    mc = crd(listGridSize,e.v1)
    nc = crd(listGridSize,e.v2)
    dist = abs.(mc.c .- nc.c)
    for i in 1:d
        if dist == ntuple(j -> i==j, d)
            return i
        end
    end
    @assert false
end

export edgeVD
"""edge (vertices) to edge (vertex,direction)"""
function edgeVD(listGridSize, evv::Edgevv)
    return Edgevd(min(evv.v1, evv.v2),direction(listGridSize, evv))
end

export expCorner
"""(m,n) label corners. in 3d n=1,...,8"""
function expCorner(listGridSize, svalue, m::Int, n::Int, a)
    d = length(listGridSize)
    r = a
    for i in 1:d
        evdi = edgeVD(listGridSize, atomCorner(listGridSize,m,n)[i])
        r *= svalue[evdi.vert, evdi.dr]
    end
    r
end

export ampCorner
function ampCorner(listGridSize, svalue, cvalue, m::Int, n::Int,a,L)
    d = length(listGridSize)
    p = 1.0
    for i in 1:d
        evd = edgeVD(listGridSize, atomCorner(listGridSize,m,n)[i])
        ss = svalue[evd.vert, evd.dr]
        ae = ampEdge(listGridSize, svalue, cvalue, edgeVD(listGridSize, atomCorner(listGridSize,m,n)[i]),L)
        ec = expCorner(listGridSize, svalue, m, n, a)
        p *= ae^(ec / ss)
    end
    return p
end



# total amplitude
export ampVG
function ampVG(listGridSize, svalue, cvalue, a,L)
    d = length(listGridSize)
    lgs = listGridSize
    las = lgs.- 1
    p = 1.0
    for i in 1:prod(las), j in 1:2^d
        #albl=atomlabel[i]
        albl = lbl(listGridSize,Coord(CartesianIndices(las)[i].I.-1))
        p *= ampCorner(listGridSize, svalue, cvalue, albl, j, a, L)
    end
    return p
end




## added

# "caustic restriction"
export smax
function smax(c,dspac) #dspc is SPATIAL dimension
    pi*sqrt(dspac/c)
end

# vary certain edge configurations

# using SparseArrays

export ampVGvar
function ampVGvar(lgs, sInitial, cInitial, sVar::SparseMatrixCSC, cVar::SparseMatrixCSC, a, L)

# sVar, cVar format: (vertex,direction,value)

    for i in 1:length(sVar.rowval)
        sInitial[findnz(sVar)[1][i],findnz(sVar)[2][i]] = findnz(sVar)[3][i]
    end

    for i in 1:length(cVar.rowval)
        cInitial[findnz(cVar)[1][i],findnz(cVar)[2][i]] = findnz(cVar)[3][i]
    end

    ampVG(lgs, sInitial, cInitial, a, L)
end


# set homogeneous (same values in bulk and on boundary) spacetime configurations

export svalueHom
function svalueHom(lgs,sv)
    d = length(lgs)
    return fill(sv,(gridSize(lgs, d),d))
end

export cvalueHom
function cvalueHom(lgs,cv)
    d = length(lgs)
    return fill(cv,(gridSize(lgs, d),d))
end

# [[remove duplicate entries?]]

export listNeighborEdgevv
function listNeighborEdgevv(sk,l)
    list = Edgevv[]
    for i in l, j in neighbors(sk,i)
        push!(list, Edgevv(i,j))
    end
    list
end

# amplitude homogeneous bulk
export ampVGHomBulk
function ampVGHomBulk(lgs, svalue, cvalue, bulks, bulkc, a, L)
    lbvs = lgs.-2 # listBulkVertexSize
    lbv = [lbl(lgs, Coord(CartesianIndices(lbvs)[i].I)) for i in 1:prod(lbvs)] # bulk vertices
    lbevd = [edgeVD(lgs, listNeighborEdgevv(gridGraph(lgs,0),lbv)[i]) for i in 1:length(listNeighborEdgevv(gridGraph(lgs,0),lbv))]; # bulk edges as (vertex,direction)

    for i in 1:length(lbevd)
        svalue[lbevd[i].vert...] = bulks ## is this correct? need to set for different dr?
        cvalue[lbevd[i].vert...] = bulkc ## is this correct? need to set for different dr?
    end
    ampVG(lgs, svalue, cvalue, a, L)
end

export ampVGHomBulkMeasure
function ampVGHomBulkMeasure(lgs, svalue, cvalue, bulks, bulkc, a, L)

lbvs = lgs.-2 # listBulkVertexSize
lbv = [lbl(lgs, Coord(CartesianIndices(lbvs)[i].I)) for i in 1:prod(lbvs)] # bulk vertices
lbevd = [edgeVD(lgs, listNeighborEdgevv(gridGraph(lgs,0),lbv)[i]) for i in 1:length(listNeighborEdgevv(gridGraph(lgs,0),lbv))]; # bulk edges as (vertex,direction)

    for i in 1:length(lbevd)
        svalue[lbevd[i].vert...] = bulks
        cvalue[lbevd[i].vert...] = bulkc
    end
    ampVG(lgs, svalue, cvalue, a, L)* prod(2 .* svalue)
end

# amplitude homogeneous bulk with caustic restriction
export ampVGHomBulkRes
function ampVGHomBulkRes(lgs, svalue, cvalue, bulks, bulkc, a, L)

lbvs = lgs.-2 # listBulkVertexSize
lbv = [lbl(lgs, Coord(CartesianIndices(lbvs)[i].I)) for i in 1:prod(lbvs)] # bulk vertices
lbevd = [edgeVD(lgs, listNeighborEdgevv(gridGraph(lgs,0),lbv)[i]) for i in 1:length(listNeighborEdgevv(gridGraph(lgs,0),lbv))]; # bulk edges as (vertex,direction)

    if 0 <= bulks <= smax(bulkc,length(lgs)-1) && 0 <= bulkc ##
        return ampVGHomBulk(lgs, svalue, cvalue, bulks, bulkc, a, L)
    else
        return 0
    end
end


# amplitude homogeneous bulk with caustic restriction
export ampVGHomBulkResMeasure
function ampVGHomBulkResMeasure(lgs, svalue, cvalue, bulks, bulkc, a, L)

lbvs = lgs.-2 # listBulkVertexSize
lbv = [lbl(lgs, Coord(CartesianIndices(lbvs)[i].I)) for i in 1:prod(lbvs)] # bulk vertices
lbevd = [edgeVD(lgs, listNeighborEdgevv(gridGraph(lgs,0),lbv)[i]) for i in 1:length(listNeighborEdgevv(gridGraph(lgs,0),lbv))]; # bulk edges as (vertex,direction)

    if 0 <= bulks <= smax(bulkc,length(lgs)-1) && 0 <= bulkc ##
        return ampVGHomBulkMeasure(lgs, svalue, cvalue, bulks, bulkc, a, L)
    else
        return 0
    end
end

end
