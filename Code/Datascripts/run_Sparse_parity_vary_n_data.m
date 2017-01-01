% Generate Trunk datasets for various values of n and p

close all
clear
clc

fpath = mfilename('fullpath');
rerfPath = fpath(1:strfind(fpath,'RandomerForest')-1);

rng(1);

ps = [3,10,20];                 % numbers of dimensions
ns{1} = [10,100,1000];          % numbers of train samples for ps(1)
ns{2} = [1000,5000,50000];      % numbers of train samples for ps(2)
ns{3} = [1000,10000,100000];    % numbers of train samples for ps(3)
ntest = 10000;                  % numbers of test samples
ntrials = 10;                   % number of replicate experiments

Xtrain = cell(length(ns),length(ps));   % training data
Ytrain = cell(length(ns),length(ps));   % training labels
Xtest = cell(1,length(ps));             % test data
Ytest = cell(1,length(ps));             % test labels
ClassPosteriors = cell(1,length(ps));

% generate data
for j = 1:length(ps)
    p = ps(j);
    fprintf('p = %d\n',p)
    p_prime = min(3,p);
    for i = 1:length(ns{j})
        ntrain = ns{j}(i);
        fprintf('n = %d\n',ntrain)
        if ntrain == 10
            Ytrain{i,j} = cell(ntrain,ntrials);
            for trial = 1:ntrials
                go = true;
                while go
                    Xtrain{i,j}(:,:,trial) = rand(ntrain,p)*2 - 1;
                    Ytrain{i,j}(:,trial) = cellstr(num2str(mod(sum(Xtrain{i,j}(:,1:p_prime,trial)>0,2),2)));
                    if mean(strcmp(Ytrain{i,j}(:,trial),'1')) == 0.5
                        go = false;
                    end
                end
            end
        else
            Xtrain{i,j} = rand(ntrain,p,ntrials)*2 - 1;
            Ytrain{i,j} = cell(ntrain,ntrials);
            for trial = 1:ntrials
                Ytrain{i,j}(:,trial) = cellstr(num2str(mod(sum(Xtrain{i,j}(:,1:p_prime,trial)>0,2),2)));
            end
        end
    end
    Xtest{j} = rand(ntest,p)*2 - 1;
    Ytest{j} = cellstr(num2str(mod(sum(Xtest{j}(:,1:p_prime)>0,2),2)));
    ClassPosteriors{j} = zeros(ntest,2);
    ClassPosteriors{j}(:,2) = cellfun(@str2double,Ytest{j});
    ClassPosteriors{j}(:,1) = 1 - ClassPosteriors{j}(:,2);
end

save('~/Documents/MATLAB/Data/Sparse_parity_vary_n_data.mat','Xtrain','Ytrain',...
    'Xtest','Ytest','ClassPosteriors','ns','ntest','ps','ntrials','-v7.3')