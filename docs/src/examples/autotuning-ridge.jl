# # Auto-tuning Hyperparameters

#md # [![](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](@__REPO_ROOT_URL__/examples/autotuning-ridge.jl)
#md # [![](https://img.shields.io/badge/show-nbviewer-579ACA.svg)](@__NBVIEWER_ROOT_URL__/generated/autotuning-ridge.ipynb)

# This example shows how to learn the hyperparameters in Ridge Regression using a gradient descent routine.  
# Let the problem be modelled as

# ```math
# \begin{equation}
# \min_{w} \quad \frac{1}{2n} \sum_{i=1}^{n} (y_{i} - w^T x_{i})^2 + \alpha \| w \|_2^2
# \end{equation}
# ```

# where 
# - `x`, `y` are the data points
# - `w` constitutes weights of the regressing line
# - `α` is the only hyperparameter acting on regularization

using DiffOpt
using Statistics
using OSQP
using JuMP
using Plots
import Random
using LinearAlgebra


"""
    R2(y_true, y_pred)

Return the coefficient of determination R2 of the prediction.
Best possible score is 1.0, it can be negative because the model can be arbitrarily worse
"""
function R2(y_true, y_pred)
    u = sum((y_pred - y_true).^2)  # Regression sum of squares
    v = sum((y_true .- mean(y_true)).^2)  # Total sum of squares
    
    return 1-(u/v)
end

# Create a non-trivial, noisy regression dataset

function create_problem(N, D, noise)
    w = rand(D) 
    X = rand(N, D) 

    # if noise=0, then there is no need of regularization and
    # alpha=0 will give the best R2 score
    y = X * w .+ noise*randn(N)

    l = N ÷ 2  # test train split
    return X[1:l, :], X[l+1:N, :], y[1:l], y[l+1:N]
end

X_train, X_test, y_train, y_test = create_problem(800, 30, 4);


# Define a helper function for regression

function fit_ridge(X, y, α)
    model = Model(() -> diff_optimizer(OSQP.Optimizer))

    N, D = size(X)
    
    @variable(model, w[1:D] >= -10)
    set_optimizer_attribute(model, MOI.Silent(), true)
    
    @objective(
        model,
        Min,
        dot(y - X*w, y - X*w)/(2N) + α * dot(w, w),
    )

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL
        error("Unexpected status: $(termination_status(model))")
    end

    loss_value = objective_value(model)
    return model, w, loss_value, value.(w)
end

# Solve the problem for several values of α

αs = [0.0, 1e-3, 2e-3, 5e-3, 1e-2, 2e-2, 5e-2, 7e-2, 2e-1, 3e-1, .5, .7, 1.0]
Rs = Float64[]
mse = Float64[]

for α in αs
    _, _, _, w_train = fit_ridge(X_train, y_train, α)
    y_pred = X_test * w_train
    push!(Rs, R2(y_test, y_pred))
    push!(mse, sum((y_pred - y_test).^2))
end

# Visualize the R2 correlation metric

plot(log.(αs), 10 * Rs, label="R2 prediction score",  xaxis = ("log(α)"))

# Visualize the Mean Score Error metric

plot(log.(αs), mse, label="MSE", xaxis = ("log(α)"))

# Define the gradient of the model with respect to the parameter α

function ∇model(model, X_train, w, ŵ, α)
    N, D = size(X_train)
    dw = zeros(D)
    ∂w_∂α = zeros(D)

    for i in 1:D
        dw[i] = 1.0 #set

        MOI.set(
            model, 
            DiffOpt.ForwardInObjective(), 
            MOI.ScalarQuadraticFunction(
                [MOI.ScalarAffineTerm(0.0, w[i].index)], 
                [MOI.ScalarQuadraticTerm(dw[i]*α, w[i].index, w[i].index)], 
                0.0
            )
        )

        DiffOpt.forward(model)  # find grad

        ∂w_∂α[i] = MOI.get(
            model,
            DiffOpt.ForwardOutVariablePrimal(), 
            w[i]
        )

        dw[i] = 0.0 #unset
    end
    return sqrt(ŵ'ŵ) + 2α*(ŵ'∂w_∂α) - sum((X_train*∂w_∂α).*(Y_train - X_train*ŵ))/(2N)
end


# Plot the gradient ∂l/∂α

∂l_∂αs = Float64[]
N, D = size(X_train)

for α in αs
    model, w, _, ŵ = fit_ridge(X_train, y_train, α)

    ∂l_∂w = [2*α*ŵ[i] - sum(X_train[:,i] .* (y_train - X_train*ŵ))/N for i in 1:D]
    @assert norm(∂l_∂w) < 1e-1  # testing optimality
    
    push!(
        ∂l_∂αs, 
        ∇model(model, X_train, w, ŵ, α)
    )
end

plot(αs, ∂l_∂αs, label="∂l/∂α",  xaxis = ("α"))



# Define helper function for Gradient Descent

"""
    descent(α, max_iters=25)

start from initial value of regularization constant
do gradient descent on alpha
until the MSE keeps on decreasing
"""
function descent(α, max_iters=25)
    prev_mse = 1e7
    curr_mse = 1e6
    
    α_s = Float64[]
    mse = Float64[]
    
    iter=0
    while curr_mse - 10 < prev_mse && iter < max_iters
        iter += 1
        model, w, _, ŵ = fit_ridge(X_train, y_train, α)
        
        ∂α = ∇model(model, X_train, w, ŵ, α) # fetch the gradient
        
        α += 0.01*∂α  # update by a fixed amount
        
        push!(α_s, α)
        
        y_pred = X_test*ŵ

        prev_mse = curr_mse
        curr_mse = sum((y_pred - y_test).^2) 
        
        push!(mse, curr_mse)
    end
    
    return α_s, mse
end

ᾱ, msē = descent(1.0);

# Visualize gradient descent and convergence 

plot(log.(αs), mse, label="MSE", xaxis = ("α"))
plot!(log.(ᾱ), msē, label="G.D. for α", lw = 2)
