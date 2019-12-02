using Distributed
addprocs(2)
@everywhere using DiffEqGPU, CuArrays, OrdinaryDiffEq, Test, Random

@everywhere begin
    function lorenz_distributed(du,u,p,t)
     @inbounds begin
         du[1] = p[1]*(u[2]-u[1])
         du[2] = u[1]*(p[2]-u[3]) - u[2]
         du[3] = u[1]*u[2] - p[3]*u[3]
     end
     nothing
    end
    CuArrays.allowscalar(false)
    u0 = Float32[1.0;0.0;0.0]
    tspan = (0.0f0,100.0f0)
    p = (10.0f0,28.0f0,8/3f0)
    Random.seed!(1)
    const pre_p_distributed = [rand(Float32,3) for i in 1:10]
    function prob_func_distributed(prob,i,repeat)
        OrdinaryDiffEq.remake(prob,p=pre_p[i].*p)
    end
end

prob = ODEProblem(lorenz_distributed,u0,tspan,p)
monteprob = EnsembleProblem(prob, prob_func = prob_func_distributed)

#Performance check with nvvp
# CUDAnative.CUDAdrv.@profile
@time sol = solve(monteprob,Tsit5(),EnsembleGPUArray(),trajectories=10,saveat=1.0f0)
@test length(filter(x -> x.u != sol.u[1].u, sol.u)) != 0 # 0 element array
@time sol = solve(monteprob,ROCK4(),EnsembleGPUArray(),trajectories=10,saveat=1.0f0)
@time sol2 = solve(monteprob,Tsit5(),EnsembleGPUArray(),trajectories=10,
                                                 batch_size=5,saveat=1.0f0)

@test length(filter(x -> x.u != sol.u[1].u, sol.u)) != 0 # 0 element array
@test length(filter(x -> x.u != sol2.u[6].u, sol.u)) != 0 # 0 element array
@test all(all(sol[i].prob.p .== pre_p[i].*p) for i in 1:10)
@test all(all(sol2[i].prob.p .== pre_p[i].*p) for i in 1:10)

#To set 1 GPU per device:
#
import CUDAdrv, CUDAnative
addprocs(numgpus)
@info "Setting up DArray{CuArray} with" N=nworkers() NCUDAdevices=length(CUDAdrv.devices())
let gpuworkers = asyncmap(collect(zip(workers(), CUDAdrv.devices()))) do (p, d)
  remotecall_wait(CUDAnative.device!, p, d)
  p
end

#=
# Provide a convenience function distributeCuda
# that will move an Array to a set of remote workers
# that have a GPU attached.
import CUDAdrv, CUDAnative
@info "Setting up DArray{CuArray} with" N=nworkers() NCUDAdevices=length(CUDAdrv.devices())
let gpuworkers = asyncmap(collect(zip(workers(), CUDAdrv.devices()))) do (p, d)
      remotecall_wait(CUDAnative.device!, p, d)
      p
  end
  @assert length(gpuworkers) == length(CUDAdrv.devices())
  global distributeCuda
  function distributeCuda(A)
      dA  = distribute(A, procs = gpuworkers)
      return DistributedArrays.map_localparts(CuArray, dA)
  end
end
=#
