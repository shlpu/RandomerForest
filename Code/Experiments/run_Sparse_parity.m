close all
clear
clc

fpath = mfilename('fullpath');
rerfPath = fpath(1:strfind(fpath,'RandomerForest')-1);

rng(1);

load Sparse_parity_data
load Random_matrix_adjustment_factor

Classifiers = {'rf' 'rfr' 'rerf' 'rerfr' 'rerfd' 'frc' 'frcr' 'rr_rf' 'rr_rfr'}; 

for i = 3:length(dims)
    p = dims(i);
    fprintf('p = %d\n',p)
      
    if p <= 5
        mtrys = [1:p ceil(p.^[1.5 2])];
    elseif p > 5 && p <= 25
        mtrys = ceil(p.^[0 1/4 1/2 3/4 1 1.5 2]);
    else
        mtrys = [ceil(p.^[0 1/4 1/2 3/4 1]) 5*p 10*p];
    end
    mtrys_rf = mtrys(mtrys<=p);

    for c = 1:length(Classifiers)
        Params{i}.(Classifiers{c}).nTrees = 500;
        Params{i}.(Classifiers{c}).Stratified = true;
        Params{i}.(Classifiers{c}).NWorkers = 24;
        if strcmp(Classifiers{c},'rfr') || strcmp(Classifiers{c},...
                'rerfr') || strcmp(Classifiers{c},'frcr') || ...
                strcmp(Classifiers{c},'rr_rfr')
            Params{i}.(Classifiers{c}).Robust = true;
        else
            Params{i}.(Classifiers{c}).Robust = false;
        end
        if strcmp(Classifiers{c},'rerfd')
            Params{i}.(Classifiers{c}).mdiff = 'node';
        else
            Params{i}.(Classifiers{c}).mdiff = 'off';
        end
        if strcmp(Classifiers{c},'rf') || strcmp(Classifiers{c},'rfr')...
                || strcmp(Classifiers{c},'rr_rf') || ...
                strcmp(Classifiers{c},'rr_rfr')
            Params{i}.(Classifiers{c}).RandomForest = true;
            Params{i}.(Classifiers{c}).d = mtrys_rf;
        else
            Params{i}.(Classifiers{c}).RandomForest = false;
            Params{i}.(Classifiers{c}).d = mtrys;
        end
        if strcmp(Classifiers{c},'rerf') || strcmp(Classifiers{c},'rerfr')...
                strcmp(Classifiers{c},'rerfd')
            Params{i}.(Classifiers{c}).Method = 'sparse-adjusted';
            for j = 1:length(Params{i}.(Classifiers{c}).d)
                Params{i}.(Classifiers{c}).dprime(j) = ...
                    ceil(Params{i}.(Classifiers{c}).d(j)^(1/interp1(ps,...
                    slope,p)));
            end
        elseif strcmp(Classifiers{c},'frc') || strcmp(Classifiers{c},'frcr')
            Params{i}.(Classifiers{c}).Method = 'frc';
            Params{i}.(Classifiers{c}).nmix = 2;
        end
        if strcmp(Classifiers{c},'rr_rf') || strcmp(Classifiers{c},'rr_rfr')
            Params{i}.(Classifiers{c}).Rotate = true;
        end

        OOBError{i}.(Classifiers{c}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));
        OOBAUC{i}.(Classifiers{c}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));
        TrainTime{i}.(Classifiers{c}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));
        
        for trial = 1:ntrials

            % train classifier
            poolobj = gcp('nocreate');
            if isempty(poolobj)
                parpool('local',Params{i}.(Classifiers{c}).NWorkers,...
                    'IdleTimeout',360);
            end

            tic;
            [Forest,~,TrainTime{i}.(Classifiers{c})(trial,:)] = ...
                RerF_train(Xtrain{i}(:,:,trial),Ytrain{i}(:,trial),...
                Params{i}.(Classifiers{c}));

            % select best hyperparameter

            for j = 1:length(Params{i}.(Classifiers{c}).d)
                Scores = rerf_oob_classprob(Forest{j},Xtrain{i}(:,:,trial),'last');
                Predictions = predict_class(Scores,Forest{j}.classname);
                OOBError{i}.(Classifiers{c})(trial,j) = ...
                    misclassification_rate(Predictions,Ytrain{i}(:,trial),...
                    false);
                if size(Scores,2) > 2
                    Yb = binarize_labels(Ytrain{i}(:,trial),Forest{j}.classname);
                    [~,~,~,OOBAUC{i}.(Classifiers{c})(trial,j)] = ...
                        perfcurve(Yb(:),Scores(:),'1');
                else
                    [~,~,~,OOBAUC{i}.(Classifiers{c})(trial,j)] = ...
                        perfcurve(Ytrain{i}(:,trial),Scores(:,2),'1');
                end
            end
            BestIdx = hp_optimize(OOBError{i}.(Classifiers{c})(trial,:),...
                OOBAUC{i}.(Classifiers{c})(trial,:));
            if length(BestIdx)>1
                BestIdx = BestIdx(end);
            end

            if ~Forest{BestIdx}.Robust
                Scores = rerf_classprob(Forest{BestIdx},Xtest{i},'last');
            else
                Scores = rerf_classprob(Forest{BestIdx},Xtest{i},...
                    'last',Xtrain{i}(:,:,trial));
            end
            Predictions = predict_class(Scores,Forest{BestIdx}.classname);
            TestError{i}.(Classifiers{c})(trial) = misclassification_rate(Predictions,...
                Ytest{i},false);

            clear Forest

            save([rerfPath 'RandomerForest/Results/Sparse_parity.mat'],'dims',...
                'OOBError','OOBAUC','TestError','TrainTime')
        end
        fprintf('%s complete\n',Classifiers{c})
    end   
end