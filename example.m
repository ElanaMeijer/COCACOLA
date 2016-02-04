addpath('nmf_bpas')

run('vlfeat-0.9.20/toolbox/vl_setup')

covInputTableURL = 'data/StrainMock/input/cov_inputtableR.tsv';
compositFileURL = 'data/StrainMock/input/kmer_4.csv';
linkageFileURL = 'data/StrainMock/input/linkage.tsv';
contigNameListURL = 'data/StrainMock/input/namelist.txt';


contigSampleCovMatURL = 'data/StrainMock/input/covMat_inputtableR.csv';
contigSampleCompositMatURL = 'data/StrainMock/input/compositMat_inputtableR.csv';
linkageMatURL = 'data/StrainMock/input/linkageMat.csv';

% preprocessing the raw input into the format required by COCACOLA
fid1 = fopen(covInputTableURL,'r');
covList = textscan(fid1,'%s',1,'Delimiter','\n');
fclose(fid1);

covHeader = cell2mat(covList{1}(1));
covHeaderArr = strsplit(covHeader,'\t');
sampleSize = length(covHeaderArr)-1;

fid2 = fopen(covInputTableURL,'r');
covTable = textscan(fid2,['%s',repmat('%.8n',[1,sampleSize])],'HeaderLines',1);
fclose(fid2);

contigsNameList = covTable{1};
contigNum = length(contigsNameList);

csvwrite(contigSampleCovMatURL, covTable(2:length(covHeaderArr)))

fid3 = fopen(compositFileURL,'r');
compositList = textscan(fid3,'%s',1,'Delimiter','\n');
fclose(fid3);

compositHeader = cell2mat(compositList{1}(1));
compositHeaderArr = strsplit(compositHeader,',');
kmerDim = length(compositHeaderArr)-1;

fid4 = fopen(compositFileURL,'r');
compositTable = textscan(fid4,['%s',repmat('%f',[1,kmerDim])],'HeaderLines',1,'Delimiter',',');
fclose(fid4);

fid5 = fopen(compositFileURL,'r');
compositTable1 = textscan(fid5,'%s','HeaderLines',1,'Delimiter','\n');
fclose(fid5);

mapObj = containers.Map(compositTable{1},compositTable1{1});

fid6 = fopen(contigSampleCompositMatURL, 'w');  
fid7 = fopen(contigNameListURL,'w');
for i=1:contigNum
    keyStr = cell2mat(contigsNameList(i));
    rowStr = mapObj(keyStr);
    fprintf(fid6,'%s\n', strrep(rowStr, strcat(keyStr,','), ''));
    fprintf(fid7,'%s\n', keyStr);
end
fclose(fid6);
fclose(fid7);

mapObj1 = containers.Map(contigsNameList,1:1:contigNum);
fid8 = fopen(linkageFileURL,'r');
linkageList = textscan(fid8,'%s',1,'Delimiter','\n');
fclose(fid8);

linkageHeader = cell2mat(linkageList{1}(1));
linkageHeaderArr = strsplit(linkageHeader,'\t');
sampleSize1 = (length(linkageHeaderArr)-2)/6;

selectIndict = [];
for i=1:sampleSize
    selectIndict = [selectIndict [1 2 3 4]+6*(i-1)];
end

fid9 = fopen(linkageFileURL,'r');
linkageTable = textscan(fid9,['%s','%s',repmat('%d',[1,sampleSize1*6])],'HeaderLines',1,'Delimiter','\t');
fclose(fid9);

linkCntMat = cell2mat(linkageTable(3: length(linkageHeaderArr)));
linkCntMat = linkCntMat(:,selectIndict);
edgeWMat = zeros(size(linkCntMat,1), sampleSize1);
for i=1:sampleSize1
    subCntMat = linkCntMat(:,[1 2 3 4]+4*(i-1));
    edgeWMat(:,i) = sum(subCntMat,2);
end

edgeWMat(edgeWMat < 10) = 0;
edgeWMat(edgeWMat > 0) = 1;
edgeW = sum(edgeWMat,2);

fid10 = fopen(linkageMatURL,'w');
edgeNum = length(linkageTable{1});
for i=1:edgeNum
    id1 = mapObj1(cell2mat(linkageTable{1}(i)));
    id2 = mapObj1(cell2mat(linkageTable{2}(i)));
    
    if edgeW(i) >= 2, fprintf(fid10,'%d\t%d\t%d\n', min(id1,id2), max(id1,id2), edgeW(i)); end
end
fclose(fid10);


% preprocessing of M (coverage matrix), first do column-wise normalization, then row-wise normalization
M = csvread(contigSampleCovMatURL); 
M = M + 1e-2;
contigNum = size(M, 1);

columnSum = sum(M, 1);
M = M ./ repmat(columnSum,size(M, 1),1);

rowSum = sum(M, 2); sM = rowSum;
M =  M ./ repmat(rowSum,1,size(M, 2));
 
% preprocessing of V (composition matrix), do the row-wise normalization
V = csvread(contigSampleCompositMatURL);
V = V + 1;
V = V ./ repmat(sum(V,2),1,size(V, 2));

% set the parameters
X = [M V]';
n = size(X, 2);
X = X * 1e4;

% choose an empirical initial OTU number k, or you can simply choose set k by yourself
kArr = 5:5:200; result = [];
for kIdx = 1: length(kArr)
    candK = kArr(kIdx);
    
    options = []; options.distance = 2; options.start = 1;
    options.repeat = 10; options.blockLen = 1;
    [~,Wpre,~] = myKmeansPar(X,candK,options);
    ratio = size(Wpre,2)/candK;
    result = [result; [candK size(Wpre,2) ratio]];
    if ratio <= 0.5, break; end     
end
k = result(end,2)*2; 
%k=48;

% initialize W and H by k-means clustering with L1-distance
[W0, label0] = vl_kmeans(X,k,'Initialization', 'RANDSEL', 'NumRepetitions', 10, 'distance', 'l1', 'algorithm', 'elkan');
label0 = double(label0)';

H0 = spconvert([label0 (1:1:length(label0))' ones(length(label0),1)]);
if size(H0,1) < size(W0,2), H0(size(W0,2),n) = 0; end;

fid = fopen(contigNameListURL,'r'); contigsNameList = textscan(fid,'%s'); fclose(fid);

outputInitWURL = 'data/StrainMock/output/W_init_full.csv';
csvwrite(outputInitWURL, W0); size(W0)

outputInitBinResultURL = 'data/StrainMock/output/clustering_init_full.csv';
fid = fopen(outputInitBinResultURL, 'w');   
for j=1:size(contigsNameList{1})    
    fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), label0(j));
end
fclose(fid);

% eliminate suspicious clusters with very few contigs using the bottom-up L Method
[Wagg, labelAgg] = clustAgg_Lmethod(X, W0, label0, 1);

Hagg = spconvert([labelAgg (1:1:length(labelAgg))' ones(length(labelAgg),1)]);
if size(Hagg,1) < size(Wagg,2), Hagg(size(Wagg,2),n) = 0; end;

outputInitWAggURL = 'data/StrainMock/output/W_initAgg_full.csv';
csvwrite(outputInitWAggURL, Wagg); size(Wagg)

outputInitAggBinResultURL = 'data/StrainMock/output/clustering_initAgg_full.csv';
fid = fopen(outputInitAggBinResultURL, 'w');   
for j=1:size(contigsNameList{1})    
    fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), labelAgg(j));
end
fclose(fid);

% run COCACOLA without using any additioanl type of information
X1 = X; W1 = Wagg; H1 = Hagg;
options = [];
options.MODE = 1;
options.W_INIT = W1;
options.H_INIT = H1;

[WaggOpt,HaggOpt,labelAggOpt] = myNMF(X1,sparse([]),size(W1,2),options);

outputWAggOptURL = 'data/StrainMock/output/W_aggOpt_full_noAddInfo.csv';
csvwrite(outputWAggOptURL, WaggOpt); size(WaggOpt)

outputAggOptBinResultURL = 'data/StrainMock/output/clustering_aggOpt_full_noAddInfo.csv';
fid = fopen(outputAggOptBinResultURL, 'w');   
for j=1:size(contigsNameList{1})    
    fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), labelAggOpt(j));
end
fclose(fid);

[WaggOptsep, labelAggOptsep] = clustAgg_SepCond(X, WaggOpt, labelAggOpt, 1);

outputWAggOptSepURL = 'data/StrainMock/output/W_aggOptSep_full_noAddInfo.csv';
csvwrite(outputWAggOptSepURL, WaggOptsep); size(WaggOptsep)

outputAggOptSepBinResultURL = 'data/StrainMock/output/clustering_aggOptSep_full_noAddInfo.csv';
fid = fopen(outputAggOptSepBinResultURL, 'w');   
for j=1:size(contigsNameList{1})    
    fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), labelAggOptsep(j));
end
fclose(fid);



% run COCACOLA with using any additional type of information
weightAdjMatURL = 'data/StrainMock/input/linkageMat.csv';
tmp = load(weightAdjMatURL);
weightMat = spconvert(tmp);
if size(weightMat,1) ~= n || size(weightMat,2) ~= n, weightMat(n,n) = 0; end
%corrMat = calCorrMat(M', 0.99);

betaArr = [1e2 1e3 5e3 1e4 5e4 1e5 5e5 1e6]; 

errArr = [];
for betaIdx = 1:length(betaArr)
	beta = betaArr(betaIdx);
    
    X1 = X; W1 = Wagg; H1 = Hagg;
    options = [];
    options.MODE = 2;
    options.BETA = beta;
    options.W_INIT = W1;
    options.H_INIT = H1;
    
    [WaggOpt,HaggOpt,labelAggOpt] = myNMF(X1,weightMat,size(W1,2),options);
    
    outputWAggOptURL = strcat(['data/StrainMock/output/W_aggOpt_full_link','_beta_',num2str(beta),'.csv']);
    csvwrite(outputWAggOptURL, WaggOpt); size(WaggOpt)

    outputAggOptBinResultURL = strcat(['data/StrainMock/output/clustering_aggOpt_full_link','_beta_',num2str(beta),'.csv']);
    fid = fopen(outputAggOptBinResultURL, 'w');   
    for j=1:size(contigsNameList{1})    
        fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), labelAggOpt(j));
    end
    fclose(fid);

    [WaggOptsep, labelAggOptsep] = clustAgg_SepCond(X, WaggOpt, labelAggOpt, 1);

    outputWAggOptSepURL = strcat(['data/StrainMock/output/W_aggOptSep_full_link','_beta_',num2str(beta),'.csv']);
    csvwrite(outputWAggOptSepURL, WaggOptsep); size(WaggOptsep)

    outputAggOptSepBinResultURL = strcat(['data/StrainMock/output/clustering_aggOptSep_full_link','_beta_',num2str(beta),'.csv']);
    fid = fopen(outputAggOptSepBinResultURL, 'w');   
    for j=1:size(contigsNameList{1})    
        fprintf(fid,'%s,%d\n', cell2mat(contigsNameList{1}(j)), labelAggOptsep(j));
    end
    fclose(fid);
    
    scoreArr = calInternalIdx(X, WaggOptsep);
    errArr = [errArr; scoreArr];
end

[~,I] = min(errArr(:,1)); 
if length(I) > 1, I = min(I); end
optBeta = betaArr(I);
fprintf('Choose optimal beta = %f \n', optBeta);

