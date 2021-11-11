const MOIT = MOI.Test

@testset "Linear tests" begin
    MOIT.contlineartest(diff_optimizer(GLPK.Optimizer), MOIT.TestConfig(basis = true), [
        "partial_start",  # see below
        "linear12",       # see below
    ])
    model = diff_optimizer(Ipopt.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.partial_start_test(
        model,
        MOIT.TestConfig(basis = true, optimal_status=MOI.LOCALLY_SOLVED, atol=ATOL, rtol=RTOL)
    )

    # This requires an infeasiblity certificate for a variable bound.
    MOIT.linear12test(
        diff_optimizer(GLPK.Optimizer),
        MOIT.TestConfig(infeas_certificates=false)
    )
end

@testset "Convex Quadratic tests" begin
    model = diff_optimizer(OSQP.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.qp1test(model, MOIT.TestConfig(atol=1e-2, rtol=1e-2))
    model = diff_optimizer(OSQP.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.qp2test(model, MOIT.TestConfig(atol=1e-2, rtol=1e-2))
    model = diff_optimizer(Ipopt.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.qp3test(
        model,
        MOIT.TestConfig(optimal_status=MOI.LOCALLY_SOLVED, atol=1e-3),
    )
end


@testset "FEASIBILITY_SENSE zeros objective" begin
    model = diff_optimizer(GLPK.Optimizer)
    MOI.set(model, MOI.Silent(), true)    
    x = MOI.add_variable(model)
    MOI.add_constraint(model, x, MOI.GreaterThan(1.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{MOI.VariableIndex}(), x)

    MOI.optimize!(model)
    @test MOI.get(model, MOI.ObjectiveValue()) ≈ 1.0 atol=ATOL rtol=RTOL
    
    MOI.set(model, MOI.ObjectiveSense(), MOI.FEASIBILITY_SENSE)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.ObjectiveValue()) >= 1.0
end

@testset "ModelLike" begin
    for opt in [GLPK.Optimizer]
        MODEL = diff_optimizer(opt)
        @testset "default_objective_test" begin
            MOIT.default_objective_test(MODEL)
        end
        @testset "default_status_test" begin
            MOIT.default_status_test(MODEL)
        end
        @testset "nametest" begin
            MOIT.nametest(MODEL)
        end
        @testset "validtest" begin
            MOIT.validtest(MODEL)
        end
        @testset "emptytest" begin
            MOIT.emptytest(MODEL)
        end
        @testset "orderedindicestest" begin
            MOIT.orderedindicestest(MODEL)
        end
        @testset "copytest" begin
            # Requires VectorOfVariables
            # MOIT.copytest(MODEL, MOIU.CachingOptimizer(
            #     diff_optimizer(GLPK.Optimizer),
            #     GLPK.Optimizer()
            # ))
        end
    end
end


@testset "Unit" begin
    MOIT.unittest(diff_optimizer(GLPK.Optimizer), MOIT.TestConfig(), [
        "number_threads", # might not work on all solvers
            
        # not testing integer constraints
        "solve_zero_one_with_bounds_1",  
        "solve_zero_one_with_bounds_2",
        "solve_zero_one_with_bounds_3",  
        "solve_integer_edge_cases",  
            
        "delete_soc_variables", 
        "solve_qcp_edge_cases",  # currently only affine or conic constraints
        "solve_objbound_edge_cases",
        "solve_qp_edge_cases",  # No quadratics
        "solve_qp_zero_offdiag",
        "update_dimension_nonnegative_variables", # TODO: fix this

        # see below
        "solve_duplicate_terms_vector_affine"
    ])
    model = diff_optimizer(SCS.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.solve_duplicate_terms_obj(model, MOIT.TestConfig())
end

@testset "basic_constraint_tests" begin
    # it contains SOCP constraints
    model = diff_optimizer(SCS.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    MOIT.basic_constraint_tests(model, MOIT.TestConfig())
end

# TODO: re-organiza conic tests
@testset "contconic.jl tests" begin
    model = diff_optimizer(SCS.Optimizer)
    MOI.set(model, MOI.Silent(), true)
    # linear tests
    for (name, test) in MOI.Test.lintests
        test(model, MOIT.TestConfig())
    end

    CONFIG_LOW_TOL = MOIT.TestConfig(atol = 1e-3, rtol = 1e-2, duals = false, infeas_certificates = false)
    # SOCP tests
    for (name, test) in MOI.Test.soctests
        test(model, CONFIG_LOW_TOL)
    end
end
