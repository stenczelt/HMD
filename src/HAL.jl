module HAL

using JuLIP
using ACE
using IPFitting
using PyCall
using LinearAlgebra
using Plots
using JuLIP.MLIPs: SumIP
using Random
using Statistics
using Distributions
using LaTeXStrings
using ASE
using HMD

function get_coeff(al, B, ncomms, weights, Vref, sparsify)
    ARDRegression = pyimport("sklearn.linear_model")["ARDRegression"]
    BRR = pyimport("sklearn.linear_model")["BayesianRidge"]

    dB = LsqDB("", B, al)
    Ψ, Y = IPFitting.Lsq.get_lsq_system(dB, verbose=true,
                                Vref=Vref, Ibasis = :,Itrain = :,
                                weights=weights, regularisers = [])

    if sparsify
        clf = ARDRegression()
        clf.fit(Ψ, Y)
        norm(clf.coef_)
        inds = findall(clf.coef_ .!= 0)

        clf = BRR()
        clf.fit(Ψ[:,inds], Y)

        S_inv = clf.alpha_ * Diagonal(ones(length(inds))) + clf.lambda_ * Symmetric(transpose(Ψ[:,inds])* Ψ[:,inds])
        S = Symmetric(inv(S_inv))
        m = clf.lambda_ * (Symmetric(S)*transpose(Ψ[:,inds])) * Y

        #for e in reverse([10.0^-i for i in 1:30])
        #    try
        d = MvNormal(m, Symmetric(S))#        d = MvNormal(m, Symmetric(S) - (minimum(eigvals(Symmetric(S))) - e)*I)
        #        break
        #    catch
        #    end
        #end
        c_samples = rand(d, ncomms);

        c = zeros(length(B))
        c[inds] = clf.coef_
        
        k = zeros(length(B), ncomms)
        for i in 1:ncomms
            _k = zeros(length(B))
            _k[inds] = c_samples[:,i]
            k[:,i] = _k
        end
        return c, k
    else
        clf = BRR()
        clf.fit(Ψ, Y)

        S_inv = clf.alpha_ * Diagonal(ones(length(Ψ[1,:]))) + clf.lambda_ * Symmetric(transpose(Ψ)* Ψ)
        S = Symmetric(inv(S_inv))
        m = clf.lambda_ * (Symmetric(S)*transpose(Ψ)) * Y

        #for e in reverse([10.0^-i for i in 1:30])
        #    try
        d = MvNormal(m, Symmetric(S))# - (minimum(eigvals(Symmetric(S))) - e)*I)
        #        break
        #    catch
        #    end
        #end
        c_samples = rand(d, ncomms);
        c = clf.coef_

        return c, c_samples
    end
end

function get_E_uncertainties(al_test, B, Vref, c, k)
    IP = SumIP(Vref, JuLIP.MLIPs.combine(B, c))

    n = length(k[1,:])
    Pl = []
    El = []
    for (i,at) in enumerate(al_test)
        E = energy(B, at.at)
        E_shift = energy(Vref, at.at)

        Es = [E_shift + sum(k[:,i] .* E) for i in 1:n];

        meanE = mean(Es)
        varE = sum([ (Es[i] - meanE)^2 for i in 1:n])/n
        push!(Pl, varE)

        e = abs.((energy(IP, at.at) .- at.D["E"][1])/length(at.at))
        push!(El, e)
    end
    return El, Pl
end

function get_F_uncertainties(al_test, B, Vref, c, k)
    IP = SumIP(Vref, JuLIP.MLIPs.combine(B, c))

    nIPs = length(k[1,:])
    nats = length(al_test)

    Pl = zeros(nats)
    Fl = zeros(nats)
    Cl = Vector(undef, nats)
    Threads.@threads for i in 1:nats
        at = al_test[i]

        E = energy(B, at.at)
        F = forces(B, at.at)

        E_shift = energy(Vref, at.at)

        Es = [E_shift + sum(k[:,i] .* E) for i in 1:nIPs];
        Fs = [sum(k[:,i] .* F) for i in 1:nIPs];

        meanE = mean(Es)
        varE = sum([ (Es[i] - meanE)^2 for i in 1:nIPs])/nIPs

        meanF = mean(Fs)
        varF =  sum([ 2*(Es[i] - meanE)*(Fs[i] - meanF) for i in 1:nIPs])/nIPs
        #varF =  sum([ (Fs[i] - meanF) for i in 1:n])/n #2*(Es[i] - meanE)*

        F = forces(IP, at.at)
        #p = (norm.(varF) ./ 0.2 + norm.(F))
        #p = sqrt(mean(vcat(varF...).^2))
        #f = maximum(vcat(F...) .- at.D["F"])
        p = maximum(norm.(varF))
        f = sqrt(mean((vcat(F...) .- at.D["F"]).^2))
        Pl[i] = p
        Fl[i] = f
        Cl[i] = configtype(at)
    end
    inds = findall(0.0 .!= Pl)
    return Fl[inds], Pl[inds], Cl[inds]
end

function HAL_E(al, al_test, B, ncomms, iters, nadd, weights, Vref; sparsify=true)
    for i in 1:iters
        @info("ITERATION $(i)")
        c, k = get_coeff(al, B, ncomms, weights, Vref, sparsify)

        IP = SumIP(Vref, JuLIP.MLIPs.combine(B, c))

        @info("HAL ERRORS OF ITERATION $(i)")
        add_fits!(IP, al, fitkey="IP2")
        rmse_, rmserel_ = rmse(al; fitkey="IP2");
        rmse_table(rmse_, rmserel_)

        El_train, Pl_train = get_E_uncertainties(al, B, Vref, c, k)
        El_test, Pl_test = get_E_uncertainties(al_test, B, Vref, c, k)
        scatter(Pl_test, El_test, yscale=:log10, xscale=:log10, legend=:bottomright, label="test")
        scatter!(Pl_train, El_train, yscale=:log10, xscale=:log10,label="train")
        xlabel!(L" \sigma^2(x)")
        ylabel!(L" \Delta E  \quad [eV/atom]")
        hline!([0.001], color="black", label="1 meV")
        savefig("HAL_E_$(i).png")

        Pl_test_fl = filter(!isnan, Pl_test)
        maxvals = sort(Pl_test_fl)[end-nadd:end]

        inds = [findall(Pl_test .== maxvals[end-i])[1] for i in 0:nadd]

        # @show("USING VASP")
        # converted_configs = []
        # for (j, selected_config) in enumerate(al_test[inds])
        #     #try
        #     #at, py_at = 
        #     HMD.CALC.VASP_calculator(selected_config.at, "HAL_$(i)", i, j, calc_settings)
        #     #catch
        #     #    @show("VASP failed?")
        #     #end
        #     #al = vcat(al, at)
        #     #push!(converted_configs, at)
        # end

        #save_configs(converted_configs, i)

        al = vcat(al, al_test[inds])
        #save_configs(al_test[inds], i)
        save_configs(al, i)
    end
end

function HAL_F(al, al_test, B, ncomms, iters, nadd, weights, Vref, plot_dict; sparsify=true)
    for i in 1:iters
        c, k = get_coeff(al, B, ncomms, weights, Vref, sparsify)

        IP = SumIP(Vref, JuLIP.MLIPs.combine(B, c))

        save_dict("./IP_HAL_$(i).json", Dict("IP" => write_dict(IP)))

        add_fits_serial!(IP, al, fitkey="IP2")
        rmse_, rmserel_ = rmse(al; fitkey="IP2");
        rmse_table(rmse_, rmserel_)

        Fl_train, Pl_train, Cl_train = get_F_uncertainties(al, B, Vref, c, k)
        Fl_test, Pl_test, Cl_test = get_F_uncertainties(al_test, B, Vref, c, k)

        train_shapes = [plot_dict[config_type] for config_type in Cl_train]
        test_shapes = [plot_dict[config_type] for config_type in Cl_test]

        scatter(Pl_test .+ 1E-6, Fl_test .+ 1E-6, markershapes=test_shapes, yscale=:log10, xscale=:log10, legend=:bottomright, label="test")
        scatter!(Pl_train .+ 1E-6, Fl_train .+ 1E-6, markershapes=train_shapes, yscale=:log10, xscale=:log10,label="train")
        xlabel!(L"\max \quad F_{\sigma^{2}} [eV/A]")
        ylabel!("F RMSE error [eV/A]")
        hline!([0.1], color="black", label="0.1 eV/A")
        savefig("HAL_F_$(i).png")

        Pl_test_fl = filter(!isnan, Pl_test)
        maxvals = sort(Pl_test_fl)[end-nadd:end]

        inds = [findall(Pl_test .== maxvals[end-i])[1] for i in 0:nadd]
        not_inds = filter!(x -> x ∉ inds, collect(1:length(al_test)))

        al = vcat(al, al_test[inds])

        save_configs(al, i, "TRAIN")
        save_configs(al_test[not_inds], i, "TEST")
    end
    return al
end

function save_configs(al, i, fname)
    py_write = pyimport("ase.io")["write"]
    al_save = []
    for at in al
        py_at = ASEAtoms(at.at)

        D_info = PyDict(py_at.po[:info])
        D_arrays = PyDict(py_at.po[:arrays])

        D_info["config_type"] = configtype(at) #"HAL_$(i)_" * configtype(at)
        try D_info["energy"] = at.D["E"] catch end
        try D_info["virial"] = [at.D["V"][1], at.D["V"][6], at.D["V"][5], at.D["V"][6], at.D["V"][2], at.D["V"][4], at.D["V"][5], at.D["V"][4], at.D["V"][3]] catch end
        try D_arrays["forces"] = reshape(at.D["F"], length(at.at), 3) catch end

        py_at.po[:info] = D_info
        py_at.po[:arrays] = D_arrays

        push!(al_save, py_at.po)
    end
    py_write("HAL_$(fname)_$(i).xyz", PyVector(al_save))
end

end