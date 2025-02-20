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
