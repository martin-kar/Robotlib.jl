Rt2T(R,t) = [R t; 0 0 0 1]
T2R(T::Matrix) = T[1:3,1:3]
T2t(T::Matrix) = T[1:3,4]
skewcoords(R) = [R[3,2];R[1,3];R[2,1]]
twistcoords(xi) = [xi[1:3, 4]; skewcoords(xi[1:3, 1:3])]
@inline skew(s) = [0 -s[3] s[2];s[3] 0 -s[1]; -s[2] s[1] 0]
@inline function skew!(R,s)
    R[1,1] = 0
    R[2,1] = s[3]
    R[3,1] = -s[2]
    R[1,2] = -s[3]
    R[2,2] = 0
    R[3,2] = s[1]
    R[1,3] = s[2]
    R[2,3] = -s[1]
    R[3,3] = 0
    return R
end
skew4(s)= [skew(s[4:6]) s[1:3]; 0 0 0 0]

# expω(w,q=1) = I + sin(norm(w)*q)/norm(w)*skew(w) + (1-cos(norm(w)*q))/norm(w)^2*skew(w)^2 # verified to work

function expω(w,q=1)
    nw = norm(w)
    if nw < 1e-12
        I + q*skew(w)
    else
        I + sin(nw*q)/nw*skew(w) + (1-cos(nw*q))/nw^2*skew(w)^2
    end
end


function expξ2(xi,q=1.0) # works well for jacobian-ikine
    v = xi[1:3]
    w = xi[4:6]
    nw = norm(w)
    what = skew(w)
    if nw < 1e-12
        eR = I + q*what
        A = q*eye(3)
    else
        eR = I + sin(nw*q)/nw*what + (1-cos(nw*q))/nw^2*what^2
        A = q*I + ((1 - cos(nw*q))/(nw^2))*what + ((nw*q - sin(nw*q))/(nw^3))*what*what
    end
    [eR A*v; 0 0 0 1]
end

"""Optimized routine to modify T in place"""
function expξ2!(T,xi,q=1.0)
    w = skew(xi[4:6])
    w2 = w^2
    nw = norm(xi[4:6])
    nw2 = nw^2
    nwq = nw*q
    snwq = sin(nwq)
    cnwq = 1-cos(nwq)
    T[1:3,1:3] = I + snwq/nw*w + cnwq/nw2*w2
    A = q*I + (cnwq/(nw2))*w + ((nwq - snwq)/(nw*nw2))*w2
    T[1:3,4] = A*xi[1:3]
end

"""
`expξ(xi,q=1.0)` calculates the exponential map of a twist with twistcoordinates xi and joint angle q
If no angle is given, q=1 is assumed
"""
function expξ(xi,q=1.0)
    expm(skew4(xi)*q)
end

"""
Calculates the matrix logarithm of a transformation matrix ∈ SE(3)
Does not seem to be very reliable for very small rotations, use logm instead, which is a bit slower.
"""
function logT(T) # Verified to work in the vicinity of I, but not for very small errors
    R = T[1:3,1:3]
    t = T[1:3,4]
    ω = logR(R)
    nω = norm(skewcoords(ω))
    if nω < 1e-3
        fact = 0.0833333
    else
        fact = (2sin(nω)-nω*(1+cos(nω)))/(2*nω^2*sin(nω))
    end
    Ai = I-0.5ω+fact*ω^2
    return [ω Ai*t;0 0 0 0]
end

"""Calculates the matrix logarithm of a rotation matrix ∈ SO(3)"""
function logR(R)
    @assert isrot(R)
    phi = acos((min(trace(R),3)-1)/2)
    if abs(phi) < 1e-10
        ω = (R-R')/2
    else
        ω = phi/(2sin(phi))*(R-R')
    end
    return ω
end

"""Calculates the adjoint of a transformation matrix"""
function ad(T)
    # Computes the adjoint of transformation matrix T
    R = T[1:3,1:3]
    t = skew(T[1:3,4])
    Z = zeros(3,3)
    A = [R t*R; Z R]
    return A
end

"""Calculates the adjoint of the inverse of a tranformation matrix T, which is also the inverse of the adjoint of T"""
function adi(T)
    # Computes the adjoint of transformation matrix inv(T)
    R = T[1:3,1:3]'
    t = skew(-R*T[1:3,4])
    Z = zeros(3,3)
    A = [R t*R; Z R]
    return A
end

"""Inverts a transformation matrix ∈ SE(3)"""
trinv(T) = [T[1:3,1:3]' -T[1:3,1:3]'*T[1:3,4];0 0 0 1]

isrot(R) = det(R[1:3,1:3]) ≈ 1 && norm(R[1:3,1:3]'R[1:3,1:3]-I) < 1e-10
isse3(T) = isrot(T) && T[4,1:4] == [0 0 0 1]

"""`Rangle(R1,R2 = eye(3),deg = false)` calculates the angle between two rotation matrices"""
function Rangle(R1,R2 = eye(3),deg = false)
    N = size(R1,3)
    if N == 1
        cosθ = (trace(R1[1:3,1:3]' * R2[1:3,1:3])-1)/2
        if cosθ > 1
            cosθ = 1
        elseif cosθ < -1
            cosθ = -1
        end
        θ = acos(cosθ)
        if deg
            θ *= 180/pi
        end
        return θ
    else
        θ = zeros(N)
        for i = 1:N
            cosθ = (trace(R1[1:3,1:3,i]' * R2[1:3,1:3,(size(R2,3)==1?1:i)])-1)/2
            if cosθ > 1
                cosθ = 1
            elseif cosθ < -1
                cosθ = -1
            end
            θ[i] = acos(cosθ)
            if deg
                θ[i] *= 180/pi
            end
        end
        return θ

    end
end

"""This is a helper method for calibPOE"""
function Ai(q,xi)
    n = size(q,1)
    A = zeros(6,6(n+1))
    qext = [q;1]
    pa = eye(6)
    for i = 1:n+1
        ω = xi[4:6,i]
        Ω = [skew(xi[4:6,i]) skew(xi[1:3,i]);
        zeros(3,3) skew(xi[4:6,i])] # This might be wrong
        θ = norm(ω)*qext[i]

        Ai = qext[i]*I + (4-θ*sin(θ) - 4cos(θ))/(2norm(ω)^2)* Ω + (4θ-5sin(θ) + θ*cos(θ))/(2norm(ω)^3) *Ω^2 + (2-θ*sin(θ) - 2cos(θ))/(2norm(ω)^4) *Ω^3 + (2θ-3sin(θ) + θ*cos(θ))/(2norm(ω)^5)* Ω^4
        A[:,(i-1)*6+1:6i] = pa*Ai
        pa = pa*ad(expξ(xi[:,i],qext[i])) # Correct order?
    end

    return A
end

"""This is the other helper method for calibPOE"""
function xii(q,xi)
    n = size(q,1)
    A = zeros(6,n)
    pa = eye(6)
    for i = 1:n
        A[:,i] = pa*xi[:,i]
        pa = pa*ad(expξ(xi[:,i],q[i])) # Correct order?
    end

    return A
end



function prodad(xi,q,n)
    pa = eye(6)
    for i = 1:n
        pa = pa*ad(expξ(skew4(xi[:,i]),q[i]))
    end
    return pa
end

function conformize(xi)
    xi[4:6] ./= norm(xi[4:6])
    xi[1:3] = xi[1:3] - (xi[4:6]'*xi[1:3])[1]*xi[4:6]
    return xi
end

"""
Calculate the (signed) angle around z axis for two rotation (transformation) matrices.
"""
function xyθ(x1,x2)
    # # Check the angle between the y-axis vectors, should go equally well with x-axis vectors, assuming angles are small
    # cosθ = x1[1:3,2]⋅x2[1:3,2]
    # # The angle error does not have sign after acos. Therefore check the angle between x and y axes and determine the sign from that
    # cosθxy = x1[1:3,1]⋅x2[1:3,2]
    # if cosθ > 1 # To avoid complex results from acos if there is some small numerical error
    #     cosθ = 1
    # end
    # θ = acos(cosθ)
    # if cosθxy < 0 # TODO: this is not properly thought through
    #     θ = -θ
    # end
    # return θ
    R2rpy(x1[1:3,1:3]'x2[1:3,1:3],conv="zyx")[3]
end

"""Takes the DH-parameters or a set of nominal transformation matrices and outputs the joint twists in base frame"""
function DH2twistsPOE(Tn)
    #This is a bit tricky, the last two twists corresponds to [tool T(0)], use with fkinePOE
    n = size(Tn,3)-1
    xi = zeros(6,n+2)
    P = skew4([0,0,0,0,0,1])
    T = eye(4)
    M = eye(4)
    for i = 1:n+1
        Xi = M*P*trinv(M)
        xi[:,i] = twistcoords(Xi)
        T = T*Tn[:,:,i]
        M = M*Tn[:,:,i]
    end
    #xi[:,end-1] = twistcoords(logT(Tn[:,:,end]))
    xi[:,end] = twistcoords(logT(T))
    return xi
end

"""Takes the DH-parameters or a set of nominal transformation matrices and outputs the joint twists in local link frames"""
function DH2twistsLPOE(Tn)
    n = size(Tn,3)
    xi = zeros(6,n)
    P = skew4([0,0,0,0,0,1])
    for i = 1:n
        Xi = trinv(Tn[:,:,i])*P*(Tn[:,:,i])
        xi[:,i] = twistcoords(Xi)
    end
    return xi
end

DH2twistsLPOE(dh::DH) = DH2twistsLPOE(dh2Tn(dh))
DH2twistsPOE(dh::DH) = DH2twistsPOE(dh2Tn(dh))

"""Takes a matrix R ∈ SO(3) or T ∈ SE(3) and makes the rotational part orthonormal"""
function toOrthoNormal!(M)
    R = M[1:3,1:3]
    U,S,V = svd(R)
    a = sign(det(U*V'))
    S = diagm([1,1,a])
    R = U*S*V'
    M[1:3,1:3] = R
    M
end

function toOrthoNormal(Mi)
    M = deepcopy(Mi)
    R = M[1:3,1:3]
    U,S,V = svd(R)
    a = sign(det(U*V'))
    S = diagm([1,1,a])
    R = U*S*V'
    M[1:3,1:3] = R
    M
end

"""
`rpy2R(r,p,y,conv="zyx")`
For rpy from ABB robot, use zyx
For rpy from Nikon, use xyz
"""
function rpy2R(r,p,y,conv="zyx")
    # ca = cos(r)
    # cb = cos(p)
    # cg = cos(y)
    # sa = sin(r)
    # sb = sin(p)
    # sg = sin(y)
    # R = [ca*cb*cg-sa*sg    -ca*cb*sg-sa*cg  ca*sb;
    # sa*cb*cg-sa*sg    -sa*cb*sg+ca*cg  sa*sb;
    # -sb*cg            sb*sg            cb]
    if conv == "zyz"
        R = rotz(r)*roty(p)*rotz(y)
    elseif conv == "xyz"
        R = rotx(r)*roty(p)*rotz(y)
    elseif conv == "zyx"
        R = rotz(r)*roty(p)*rotx(y)
    end
end

rpy2R(r,conv="zyx") = rpy2R(r...,conv)


function rotx(t, deg=false)
    if deg
        t = t *pi/180
    end
    ct = cos(t)
    st = sin(t)
    R = [
    1   0    0
    0   ct  -st
    0   st   ct
    ]
end

function roty(t, deg=false)
    if deg
        t = t *pi/180
    end
    ct = cos(t)
    st = sin(t)
    R = [
    ct  0   st
    0   1   0
    -st  0   ct
    ]
end

function rotz(t, deg=false)
    if deg
        t = t *pi/180
    end
    ct = cos(t)
    st = sin(t)
    R = [
    ct  -st  0
    st   ct  0
    0    0   1
    ]
end

"""
`R2rpy(R; conv="xyz", deg = false)`\n
If `conv` is not `xyz`, it will be `zyx`\n
returns a vector ∈ R3 or a matrix ∈ R3×N depending on the dimension of the input
"""
function R2rpy{T}(m::AbstractArray{T,3}; conv="xyz", deg = false)
    N = size(m,3)
    rpy = Array(Float64,3,N)
    for i = 1:N
        rpy[:,i] = R2rpy(m[:,:,i], conv=conv, deg=deg)
    end
    return rpy
end

function R2rpy(m::Matrix; conv="xyz", deg = false)

    rpy = zeros(3)

    if conv == "xyz"
        # XYZ order
        if abs(m[3,3]) < eps() && abs(m[2,3]) < eps()
            # singularity
            rpy[1] = 0;  # roll is zero
            rpy[2] = atan2(m[1,3], m[3,3])  # pitch
            rpy[3] = atan2(m[2,1], m[2,2])  # yaw is sum of roll+yaw
        else
            rpy[1] = atan2(-m[2,3], m[3,3])        # roll
            # compute sin/cos of roll angle
            sr = sin(rpy[1])
            cr = cos(rpy[1])
            rpy[2] = atan2(m[1,3], cr * m[3,3] - sr * m[2,3])  # pitch
            rpy[3] = atan2(-m[1,2], m[1,1])        # yaw
        end
    else
        # old ZYX order (as per Paul book)
        if abs(m[1,1]) < eps() && abs(m[2,1]) < eps()
            # singularity
            rpy[1] = 0     # roll is zero
            rpy[2] = atan2(-m[3,1], m[1,1])  # pitch
            rpy[3] = atan2(-m[2,3], m[2,2])  # yaw is difference yaw-roll
        else
            rpy[1] = atan2(m[2,1], m[1,1])
            sp = sin(rpy[1])
            cp = cos(rpy[1])
            rpy[2] = atan2(-m[3,1], cp * m[1,1] + sp * m[2,1])
            rpy[3] = atan2(sp * m[1,3] - cp * m[2,3], cp*m[2,2] - sp*m[1,2])
        end
    end
    if deg
        rpy *= 180/π
    end
    return rpy
end

using Quaternions
import Quaternions.Quaternion
function Quaternion{P}(t::Matrix{P})
    qs = sqrt(trace(t[1:3,1:3])+1)/2.0
    kx = t[3,2] - t[2,3]   # Oz - Ay
    ky = t[1,3] - t[3,1]   # Ax - Nz
    kz = t[2,1] - t[1,2]   # Ny - Ox

    if t[1,1] >= t[2,2] && t[1,1] >= t[3,3]
        kx1 = t[1,1] - t[2,2] - t[3,3] + 1 # Nx - Oy - Az + 1
        ky1 = t[2,1] + t[1,2]          # Ny + Ox
        kz1 = t[3,1] + t[1,3]          # Nz + Ax
        add = kx >= 0
    elseif t[2,2] >= t[3,3]
        kx1 = t[2,1] + t[1,2]          # Ny + Ox
        ky1 = t[2,2] - t[1,1] - t[3,3] + 1 # Oy - Nx - Az + 1
        kz1 = t[3,2] + t[2,3]          # Oz + Ay
        add = ky >= 0
    else
        kx1 = t[3,1] + t[1,3]          # Nz + Ax
        ky1 = t[3,2] + t[2,3]          # Oz + Ay
        kz1 = t[3,3] - t[1,1] - t[2,2] + 1 # Az - Nx - Oy + 1
        add = kz >= 0
    end

    if add
        kx = kx + kx1
        ky = ky + ky1
        kz = kz + kz1
    else
        kx = kx - kx1
        ky = ky - ky1
        kz = kz - kz1
    end
    nm = norm([kx, ky, kz])
    if nm == 0
        q = Quaternion(1, 0, 0, 0)
    else
        s  = sqrt(1 - qs^2) / nm
        qv = s*[kx, ky, kz]
        q  = Quaternion(qs,qv)
    end
end

function traj2quat(T)
    N = size(T,3)
    Q = Array(Float64,4,N)
    for i = 1:N
        q = Quaternion(T[:,:,i])
        Q[1,i] = q.s
        Q[2,i] = q.v1
        Q[3,i] = q.v2
        Q[4,i] = q.v3
    end
    return Q
end

@deprecate smartDiff centralDiff

function centralDiff(v)
    c = size(v,2)
    a1 = [zeros(1,c);diff(v)]
    a2 = [diff(v);zeros(1,c)]
    a = (a1+a2)/2
end
