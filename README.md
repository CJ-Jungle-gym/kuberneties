## 로컬에서 kuberneties 배포 테스트 방법
#### 1. 기본 세팅
kubectl version --client
kind version
minikube version

#### 2. Kubernetes CLI 명령어 테스트
터미널에서 실행 : kubectl get nodes
만약 Kubernetes 노드가 표시되지 않는다면, Minikube 또는 KIND 클러스터를 시작
minikube start --driver=docker
kind create cluster --name my-cluster

#### 3.YAML 파일 작성

#### 4. 배포
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

상태확인
kubectl get pods
kubectl get svc

#### 5. 브라우저에서 확인
minikube service my-nginx-service --url
출력된 url 접속
ex. http://192.168.49.2:30080

<br><br>

## 로컬에서 argoCD 배포 방법
#### 1. AWS EKS (Elastic Kubernetes Service) 클러스터에 연결할 수 있도록 kubeconfig 파일을 업데이트 
aws eks --region ap-northeast-2 update-kubeconfig --name DEVEKS

#### 2. ArgoCD 네임스페이스 생성 
kubectl create namespace argocd

#### 3. ArgoCD 설치  
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

#### 4. ArgoCD 서버 서비스 노출  
kubectl patch svc argocd-server -n argocd -p "{\"spec\": {\"type\": \"LoadBalancer\"}}"

#### 5. 로그인용 비번확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
argocd admin initial-password -n argocd

#### 6. argocd-server 로드밸런서에서 접속 DNS 확인후 접속 → 로그인하여 상태확인가능 ( admin / 확인한 초기 비밀번호 )
kubectl get -n argocd svc

#### 이후부터는 argocd-application.yaml 적용으로 자동화 가능!
kubectl apply -f https://raw.githubusercontent.com/CJ-Jungle-gym/kuberneties/main/manifest/argocd-application.yaml

<br><br>

## AWS에 cloudformation 으로 인프라를 세우고 EKS 올리기
#### 1. 기본 세팅
aws --version
helm version
eksctl version

#### 2. aws에 연결하기. 
aws configure
위 명령어를 치고 사용자의 access key > secret access key > region > json 입력
aws configure 로 한번더 잘 적용되었는지 확인

#### 3. Prod.yaml파일로 cloudformation stack 만들기
aws cloudformation create-stack --stack-name <스택 이름> --template-body file://Prod.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DBUsername,ParameterValue=dbadmin ParameterKey=DBPassword,ParameterValue=SecurePassword123
파라미터 키는 DBdml 유저와 비번을 설정하는 것. 비번은 최소 8글자 [a-zA-Z0-9] 규칙에 맞게 작성

#### 4. EKS 들어가기 (EKS 생성 완료시 사용)
aws eks update-kubeconfig --region <ap-northeast-2> --name Prod-Eks

#### 5. EKS 네임 스페이스 변경하기 (노드 그룹 생성 뒤 사용)
kubectl config set-context --current --namespace=kube-system

#### 6. EKS OIDC-Provider 생성하기
eksctl utils associate-iam-oidc-provider --region= ap-northeast-2 --cluster Prod-Eks --approve

#### 7. ALB Controller 설치하기 
먼저 ALB Controller가 가지고 있어야하는 정책이 필요함 iam_policy.json파일로 아래와 같은 정책 생성 명령어 실행.
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json  
정책이 생성 되었으면 해당 정책으로 가서 arn 주소를 확인하고 사용.
eksctl create iamserviceaccount --region ap-northeast-2 --name aws-load-balancer-controller --namespace kube-system --cluster Prod-Eks --attach-policy-arn <위 정책 arn 주소> --override-existing-serviceaccounts --approve
ALB Controller 설치하기 (EKS가 있는 VPC ID 확인)
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller --set clusterName=Prod-Eks --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=ap-northeast-2 --set vpcId=<vpc ID> -n kube-system
kubectl get pod로 ALB controller 가 잘 작동하고 있는지 확인

#### 7. 백, 프론트, ALB 올리기
파일 수정
back-deployment.yaml 파일 수정 > ECR 이미지 arn 주소 사용할 것으로 변경
back-service.yaml > 변경 사항 없음
front-deployment.yaml 파일 수정 > ECR 이미지 arn 주소 사용할 것으로 변경
front-service.yaml 파일 수정 > 서브넷 아이디, alb를 설치할 퍼블릭 ID로 변경 2개 필요
kubectl apply -f ./<파일명>.yaml 으로 deployment > service 순으로 실행 
kubectl get pod (pod 실행 확인)> kubectl get svc (서비스 실행 확인) > kubectl get ingress (ALB 잘 떠있는지 확인 주소가 떠있으면 성공)

#### 8. Karpenter, HPA 적용 과정 정리 
Karpenter
https://www.notion.so/Karpenter-YAML-1a32ef28669a806998bde6cfcd92a4c3
HPA
https://www.notion.so/HPA-Horizontal-Pod-Autoscaler-1a32ef28669a8038a740ffb7181bbe53

