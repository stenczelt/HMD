module COM

using JuLIP, Distributions, LinearAlgebra
using JuLIP.MLIPs: SumIP
using HMD
using Random

export VelocityVerlet_com, get_com_energy_forces

function VelocityVerlet_com(Vref, B, c, k, at, dt; τ = 0.0)
    varE, varF, meanF = get_com_energy_forces(Vref, B, c, k, at)
    F = meanF - τ * varF
      
    P = at.P + (0.5 * dt * F) 

    set_positions!(at, at.X + (dt*(at.P ./ at.M) ))
    set_momenta!(at, P)

    varE, varF, meanF = get_com_energy_forces(Vref, B, c, k, at)
    F = meanF - τ * varF
      
    P = at.P + (0.5 * dt * F) 
    set_momenta!(at, P)

    #p = maximum((norm.(varF) ./ (norm.(F) .+ minF)))
    p = maximum((norm.(varF)))

    return at, p
end

function VelocityVerlet_com_langevin(Vref, B, c, k, at, dt, T; γ=0.02, τ = 0.0)
    varE, varF, meanF = get_com_energy_forces(Vref, B, c, k, at)
    F = meanF - τ * varF
      
    P = at.P + (0.5 * dt * F) 
    P = random_p_update(P, at.M, γ, T, dt)

    set_positions!(at, at.X + (dt*(at.P ./ at.M) ))
    set_momenta!(at, P)

    varE, varF, meanF = get_com_energy_forces(Vref, B, c, k, at)
    F = meanF - τ * varF
      
    P = at.P + (0.5 * dt * F) 
    P = random_p_update(P, at.M, γ, T, dt)
    set_momenta!(at, P)

    #p = maximum((norm.(varF) ./ (norm.(F) .+ minF)))
    p = maximum((norm.(varF)))

    return at, p
end

function random_p_update(P, M, γ, T, dt)
    V = P ./ M
    R = rand(Normal(), (length(M)*3)) |> vecs
    c1 = exp(-γ*dt)
    c2 = sqrt(1-c1^2)*sqrt.(T ./ M)
    #@show c1, c2
    V_new = c1*V + c2 .* R
    return V_new .* M
end

# function get_com_energy_forces(IP, IPs, at)
#     #E_shift = energy(Vref, at)
#     nIPs = length(IPs)

#     E = energy(IP, at)
#     F = forces(IP, at)
    
#     Es = [energy(IPs[i], at) for i in 1:nIPs];
#     Fs = [forces(IPs[i], at) for i in 1:nIPs];
    
#     varF =  sum([ 2*(Es[i] - E)*(Fs[i] - F) for i in 1:nIPs])/nIPs
    
#     #meanE = mean(Es)
#     varE = sum([ (Es[i] - E)^2 for i in 1:nIPs])/nIPs
    
#     #meanF = mean(Fs)
    
#     return varE, varF
# end

function get_com_energy_forces(Vref, B, c, k, at)
    nIPs = length(k[1,:])
    #E_shift = energy(Vref, at)
    E = energy(B, at)
    F = forces(B, at)

    E_shift = energy(Vref, at)

    Es = [(E_shift + sum(k[:,i] .* E)) for i in 1:nIPs];
    Fs = [sum(k[:,i] .* F) for i in 1:nIPs];

    meanE = E_shift + sum(c .* E)
    meanF = sum(c .* F)

    varE = sum([ (Es[i] - meanE)^2 for i in 1:nIPs])/nIPs
    varF =  sum([ 2*(Es[i] - meanE)*(Fs[i] - meanF) for i in 1:nIPs])/nIPs
    #varF =  sum([ 2*(Es[i] - meanE)*(Fs[i] - meanF) for i in 1:nIPs])/nIPs
    # meanE = (E_shift + sum(c .* E))/nats
    # varE = sum([ (Es[i] - meanE)^2 for i in 1:nIPs])/nIPs

    #stdF = sqrt(sum(vcat([vcat(Fs[m]...) .- vcat(meanF...) for m in 1:nIPs]...).^2)/length(nIPs))
    #meanF = mean(Fs)
    
    return varE, varF, meanF
end

# function get_com_energy_forces(F, IPs, B, c_samples, at; var=var)
#     #E_shift = energy(Vref, at)

#     nIPs = length(IPs)

#     #E_b = energy(B, at)
#     F_b = forces(B, at)
    
#     mean_site_Es, Es = HMD.HAL._get_sites(IPs, at)
#     Fs = [sum(c_samples[:,i] .* F_b) for i in 1:nIPs];
    
#     varE = sum([ (Es[i] .- mean_site_Es).^2 for i in 1:nIPs])/nIPs

#     if var
#         varF =  sum([ 2*(Es[i,:] .- mean_site_Es) .* (Fs[i] - F) for i in 1:nIPs])/nIPs
#     else
#         varF =  ( sum([ 2*(Es[i,:] .- mean_site_Es) .* (Fs[i] - F) for i in 1:nIPs])/nIPs ) / varE
#     end
    
#     return varE, varF
# end

end