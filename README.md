# kuberneties

# 로컬에서 kuberneties 배포 테스트 방법
## 1. 기본 세팅
kubectl version --client
kind version
minikube version

## 2. Kubernetes CLI 명령어 테스트
터미널에서 실행 : kubectl get nodes
만약 Kubernetes 노드가 표시되지 않는다면, Minikube 또는 KIND 클러스터를 시작
minikube start --driver=docker
kind create cluster --name my-cluster

## 3.YAML 파일 작성

## 4. 배포
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

상태확인
kubectl get pods
kubectl get svc

## 5. 브라우저에서 확인
minikube service my-nginx-service --url
출력된 url 접속
ex. http://192.168.49.2:30080

