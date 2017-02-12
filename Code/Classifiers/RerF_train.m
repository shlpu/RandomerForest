function [Forest,Params,TrainTime] = RerF_train(Xtrain,Ytrain,Params)
% FUNCTION RERF_TRAIN() trains a random(er) forest classifier
% 
% Xtrain is an ntrain x p matrix of input values.
% 
% Ytrain is an ntrain x 1 cell array of strings of class labels
% 
% Params is a structure specifying algorithm parameters with fields:
% 
%   nTrees: number of trees (default = 500).
% 
%   ForestMethod: 'rerf' (default) or 'rf'
% 
%   RandomMatrix: method for contructing random matrix when ForestMethod is
%   set to 'rerf'. Options include:
% 
%       'binary' (default) - random matrix is generated by randomly placing 
%       rho*p*d nonzeros in a p x d matrix. Half of nonzeros are set to 1 and 
%       the other half are set to -1. rho is the density (proportion of 
%       nonzeros) of the random matrix.
% 
%       'continuous' - random matrix is generated by uniformly randomly 
%       placing rho*p*d nonzeros in a p x d matrix. Values of nonzeros are 
%       sampled uniformly on the interval [-1,1].
% 
%       'frc' - random matrix is generated by randomly placing L nonzeros
%       per column in a p x d matrix. Values of nonzeros are sampled
%       uniformly on the interval [-1,1].
% 
%   d: width of the random matrix when ForestMethod is set to 'rerf', or 
%   number of variables to sample when ForestMethod is set to 'rf'.
%   (default = ceil(p^(2/3))). When ForestMethod is 'rf', the maximum
%   possible value is p. There is no maximum for 'rerf'.
% 
%   L: number of nonzeros per column in the random matrix when ForestMethod
%   is set to 'rerf' and RandomMatrix is set to 'frc' (default = 2).
% 
%   rho: density of random matrix when ForestMethod is set to 'rerf' and
%   RandomMatrix is set to either 'binary' or 'continuous' (default = 1/p).
% 
%   Rotate: logical true indicates randomly rotate bootstrapped data prior 
%           to inducing trees.
% 
%   mdiff: 'node' indicates compute mean difference vector at each split
%          node and evaluate candidate projection onto this vector.
% 
%   Rescale: data preprocessing step that transforms the data prior to
%   training. Possible transformations include 'rank', 'normalize', and
%   'zscore'.
% 
%   Stratified: logical true indicates stratify bootstraps by class.
% 
%   NWorkers: number of workers for inducing trees in parallel.

p = size(Xtrain,2);

Params.AdjustmentFactors.slope = [0.7205 0.7890 0.8143 0.8298 0.8442 0.8600 0.8794 0.8916 0.8922];
Params.AdjustmentFactors.dims = [2 5 10 25 50 100 250 500 1000];
% Params.AdjustmentFactors = load('Random_matrix_adjustment_factor');

% set defaults if empty

if ~isfield(Params,'nTrees')
    Params.nTrees = 500;
end

if ~isfield(Params,'ForestMethod')
    Params.ForestMethod = 'rerf';
end

if ~isfield(Params,'RandomMatrix')
    Params.RandomMatrix = 'binary';
end

if ~isfield(Params,'Rotate')
    Params.Rotate = false;
end

if ~isfield(Params,'mdiff')
    Params.mdiff = 'off';
end

if ~isfield(Params,'d')
    if strcmp(Params.ForestMethod,'rf')
        if p <= 5
            Params.d = 1:p;
        else
            Params.d = ceil(p.^[1/4 1/2 3/4 1]);
        end
    else
        if p <= 5
            Params.d = [1:p ceil(p.^[1.5 2])];
        elseif p > 5 && p <= 10
            Params.d = ceil(p.^[1/4 1/2 3/4 1 1.5 2]);
        else
            Params.d = [ceil(p.^[1/4 1/2 3/4 1]) 5*p 10*p];
        end
    end
end

if ~isfield(Params,'rho')
    Params.rho = 1/p;
else
    if any(Params.rho <= 0 | Params.rho > 1)
        error('Parameter rho must be specified as a value in (0,1]');
    end
end

if ~isfield(Params,'dprime')
    for i = 1:length(Params.d)
        Params.dprime(i) = ceil(Params.d(i)^(1/interp1(Params.AdjustmentFactors.dims,Params.AdjustmentFactors.slope,p)));
    end
end

if ~isfield(Params,'dx')
    Params.dx = p;
end

if ~isfield(Params,'L')
    Params.L = 2;
end

if ~isfield(Params,'Rescale')
    Params.Rescale = 'off';
end

if ~isfield(Params,'Stratified')
    Params.Stratified = true;
end

if ~isfield(Params,'NWorkers')
    Params.NWorkers = 2;
end

if ~isfield(Params,'Stream')
    Params.Stream = [];
end

if ~isfield(Params,'MinParent')
    Params.MinParent = 2;
end

if ~isfield(Params,'MinLeaf')
    Params.MinLeaf = 1;
end

if ~isfield(Params,'DownsampleNode')
    Params.DownsampleNode = false;
end

if ~isfield(Params,'MaxNodeSize')
    Params.MaxNodeSize = 100;
end

TrainTime = NaN(1,length(Params.d));

poolobj = gcp('nocreate');
if isempty(poolobj)
    parpool('local',Params.NWorkers,...
        'IdleTimeout',360);
end

%train classifier for all values of Params.d

if strcmp(Params.ForestMethod,'rerf') && strcmp(Params.RandomMatrix,'frc')
    for i = 1:length(Params.L)
        for j = 1:length(Params.d)
            tic;
            if Params.L(i) == 1 && Params.d(j) > p
                Forest{(i-1)*length(Params.d)+j} = [];
                TrainTime((i-1)*length(Params.d)+j) = NaN;
            else
                Forest{(i-1)*length(Params.d)+j} = rpclassificationforest(Xtrain,Ytrain,...
                    'nTrees',Params.nTrees,...
                    'ForestMethod',Params.ForestMethod,...
                    'RandomMatrix',Params.RandomMatrix,...
                    'rotate',Params.Rotate,...
                    'mdiff',Params.mdiff,...
                    'nvartosample',Params.d(j),...
                    'rho',Params.rho,...
                    'dprime',Params.dprime(j),...
                    'nmix',Params.L(i),...
                    'Rescale',Params.Rescale,...
                    'Stratified',Params.Stratified,...
                    'NWorkers',Params.NWorkers,...
                    'stream',Params.Stream,...
                    'minparent',Params.MinParent,...
                    'minleaf',Params.MinLeaf,...
                    'DownsampleNode',false,...
                    'MaxNodeSize',100);
                TrainTime((i-1)*length(Params.d)+j) = toc;
            end
        end
    end
elseif strcmp(Params.ForestMethod,'rerf') && ~strcmp(Params.RandomMatrix,'frc')
    for i = 1:length(Params.rho)
        for j = 1:length(Params.d)
            tic;
            Forest{(i-1)*length(Params.d)+j} = rpclassificationforest(Xtrain,Ytrain,...
                'nTrees',Params.nTrees,...
                'ForestMethod',Params.ForestMethod,...
                'RandomMatrix',Params.RandomMatrix,...
                'rotate',Params.Rotate,...
                'mdiff',Params.mdiff,...
                'nvartosample',Params.d(j),...
                'rho',Params.rho(i),...
                'dprime',Params.dprime(j),...
                'Rescale',Params.Rescale,...
                'Stratified',Params.Stratified,...
                'NWorkers',Params.NWorkers,...
                'stream',Params.Stream,...
                'minparent',Params.MinParent,...
                'minleaf',Params.MinLeaf,...
                'DownsampleNode',false,...
                'MaxNodeSize',100);
                TrainTime((i-1)*length(Params.d)+j) = toc;
        end
    end
else
    for i = 1:length(Params.d)
        tic;
        Forest{i} = rpclassificationforest(Xtrain,Ytrain,...
            'nTrees',Params.nTrees,...
            'ForestMethod',Params.ForestMethod,...
            'RandomMatrix',Params.RandomMatrix,...
            'rotate',Params.Rotate,...
            'mdiff',Params.mdiff,...
            'nvartosample',Params.d(i),...
            'rho',Params.rho,...
            'dprime',Params.dprime(i),...
            'nmix',Params.L,...
            'Rescale',Params.Rescale,...
            'Stratified',Params.Stratified,...
            'NWorkers',Params.NWorkers,...
            'stream',Params.Stream,...
            'AdjustmentFactors',Params.AdjustmentFactors,...
            'dx',Params.dx,...
            'minparent',Params.MinParent,...
            'minleaf',Params.MinLeaf,...
            'DownsampleNode',false,...
            'MaxNodeSize',100);
        TrainTime(i) = toc;
    end
end