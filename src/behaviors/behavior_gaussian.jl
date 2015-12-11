export
    VehicleBehaviorGaussian,
    SG_TrainParams

# The vehicle drives following a multivariable Gaussian noise over accel & turnrate
type VehicleBehaviorGaussian <: AbstractVehicleBehavior
    Σ::MvNormal # with action vector (accel, turnrate)

    # preallocated memory
    action::Vector{Float64}

    function VehicleBehaviorGaussian(σ_lat::Float64, σ_lon::Float64, σ_correlation::Float64=0.0)
        new(MvNormal([σ_lat σ_correlation; σ_correlation σ_lon]), [0.0,0.0])
    end
    function VehicleBehaviorGaussian(Σ::MvNormal)
        @assert(length(Σ) == 2)
        new(Σ, [0.0,0.0])
    end
end

type SG_TrainParams <: AbstractVehicleBehaviorTrainParams
    SG_TrainParams() = new()
end

type SG_PreallocatedData <: AbstractVehicleBehaviorPreallocatedData

    # TODO(tim): use this

    SG_PreallocatedData(dset::ModelTrainingData, params::SG_TrainParams) = new()
    SG_PreallocatedData(dset::ModelTrainingData2, params::SG_TrainParams) = new()
end
function preallocate_learning_data(
    dset::ModelTrainingData,
    params::SG_TrainParams)

    SG_PreallocatedData(dset, params)
end
function preallocate_learning_data(
    dset::ModelTrainingData2,
    params::SG_TrainParams)

    SG_PreallocatedData(dset, params)
end

function select_action(
    basics::FeatureExtractBasicsPdSet,
    behavior::VehicleBehaviorGaussian,
    carind::Int,
    validfind::Int
    )

    Distributions._rand!(behavior.Σ, behavior.action)

    action_lat = behavior.action[1]
    action_lon = behavior.action[2]

    (action_lat, action_lon)
end

function calc_action_loglikelihood(
    ::FeatureExtractBasicsPdSet,
    behavior::VehicleBehaviorGaussian,
    ::Int,
    ::Int,
    action_lat::Float64,
    action_lon::Float64
    )

    #=
    Compute the log-likelihood of the action taken during a single frame
    given the VehicleBehaviorGaussian.
    =#

    behavior.action[1] = action_lat
    behavior.action[2] = action_lon

    logpdf(behavior.Σ, behavior.action)
end
function calc_action_loglikelihood(
    behavior::VehicleBehaviorGaussian,
    features::DataFrame,
    frameind::Integer,
    )

    behavior.action[1] = features[frameind, symbol(FUTUREDESIREDANGLE_250MS)]::Float64
    behavior.action[2] = features[frameind, symbol(FUTUREACCELERATION_250MS)]::Float64

    logpdf(behavior.Σ, behavior.action)
end

function train(
    training_data::ModelTrainingData,
    preallocated_data::SG_PreallocatedData,
    params::SG_TrainParams,
    fold::Int,
    fold_assignment::FoldAssignment,
    match_fold::Bool,
    )

    trainingframes = training_data.dataframe_nona
    nframes = size(trainingframes, 1)

    total = 0
    trainingmatrix = Array(Float64, 2, nframes)
    for i = 1 : nframes

        # TODO(tim): shouldn't use hard-coded symbols
        action_lat = trainingframes[i, :f_des_angle_250ms]
        action_lon = trainingframes[i, :f_accel_250ms]

        if !isnan(action_lat) && !isnan(action_lon) &&
           !isinf(action_lat) && !isinf(action_lon)

            total += 1
            trainingmatrix[1, total] = action_lat
            trainingmatrix[2, total] = action_lon
        end
    end
    trainingmatrix = trainingmatrix[:, 1:total]

    VehicleBehaviorGaussian(fit_mle(MvNormal, trainingmatrix))
end