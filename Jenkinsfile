pipeline 
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    buildDiscarder(logRotator(numToKeepStr: '25'))
    timeout(time: 45, unit: 'MINUTES')
  }

  environment {
    AWS_REGION      = 'us-east-1'
    AWS_ACCOUNT_ID  = '051826742726'
    ECR_REPO        = 'mag_repo'
    APP_NAME        = 'mag-app'

    ECS_CLUSTER_QA  = 'mag-ecs-cluster-qa'
    ECS_SERVICE_QA  = 'mag-ecs-svc-qa'
    ECS_TASK_QA     = 'mag-ecs-task-qa'

    ECS_CLUSTER_PRD = 'mag-ecs-cluster-prod'
    ECS_SERVICE_PRD = 'mag-ecs-svc-prod'
    ECS_TASK_PRD    = 'mag-ecs-task-prod'

    ECR_URI         = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
  }

  triggers { pollSCM('@daily') }

  stages 

    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          env.VERSION = sh(script: "git describe --tags --always || echo ${env.GIT_COMMIT_SHORT}", returnStdout: true).trim()
        }
        echo "VERSION=${env.VERSION}"
      }
    }

    stage('Build & Unit Test') 
      steps {
        sh '''
          if [ -f mvnw ]; then ./mvnw -B -q clean verify; 
          elif command -v mvn >/dev/null 2>&1; then mvn -B -q clean verify; 
          else echo "No Maven wrapper or mvn found; skipping build"; fi
        '''
      }
      post 
        always  junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' }
      
    

    stage('Static Analysis (SonarQube)') {
      when { expression { return fileExists('pom.xml') || fileExists('sonar-project.properties') } }
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          withSonarQubeEnv('sonar') {
            sh '''
              if [ -f mvnw ]; then ./mvnw -B sonar:sonar -Dsonar.login=$SONAR_TOKEN;
              elif command -v mvn >/dev/null 2>&1; then mvn -B sonar:sonar -Dsonar.login=$SONAR_TOKEN;
              else sonar-scanner -Dsonar.login=$SONAR_TOKEN || true; fi
            '''
          }
        }
      }
    }

    stage('Quality Gate') {
      when { expression { return env.SONAR_HOST_URL != null } }
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Security Scans') {
      steps {
        sh '''
          if command -v trivy >/dev/null 2>&1; then
            trivy fs --exit-code 1 --no-progress .
          else
            echo "Trivy not installed on agent; skipping image scan pre-build"
          fi
        '''
      }
    }

    stage('Docker Build & Push (ECR)') {
      steps {
        withAWS(region: "${AWS_REGION}", credentials: 'aws-creds') {
          sh '''
            aws ecr describe-repositories --repository-names ${ECR_REPO} >/dev/null 2>&1 || \
              aws ecr create-repository --repository-names ${ECR_REPO} >/dev/null

            aws ecr get-login-password --region ${AWS_REGION} | \
              docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

            docker build -t ${ECR_URI}:${VERSION} -t ${ECR_URI}:latest .
            docker push ${ECR_URI}:${VERSION}
            docker push ${ECR_URI}:latest

            echo "IMAGE=${ECR_URI}:${VERSION}" > build.env
          '''
        }
      }
    }

    stage('Deploy to QA (ECS)') {
      steps {
        withAWS(region: "${AWS_REGION}", credentials: 'aws-creds') {
          sh '''
            source build.env
            chmod +x deploy/ecs-deploy.sh
            ./deploy/ecs-deploy.sh \
              --cluster "${ECS_CLUSTER_QA}" \
              --service "${ECS_SERVICE_QA}" \
              --taskdef "${ECS_TASK_QA}" \
              --image "${IMAGE}" \
              --region "${AWS_REGION}"
          '''
        }
      }
    }

    stage('Smoke Tests (QA)') {
      steps {
        sh '''
          echo "Run your smoke tests here (curl health check, pytest, etc.)"
        '''
      }
    }

    stage('Manual Approval to PROD') {
      steps {
        input message: 'Promote this build to PRODUCTION?'
      }
    }

    stage('Deploy to PROD (ECS)') {
      steps {
        withAWS(region: "${AWS_REGION}", credentials: 'aws-creds') {
          sh '''
            source build.env
            chmod +x deploy/ecs-deploy.sh
            ./deploy/ecs-deploy.sh \
              --cluster "${ECS_CLUSTER_PRD}" \
              --service "${ECS_SERVICE_PRD}" \
              --taskdef "${ECS_TASK_PRD}" \
              --image "${IMAGE}" \
              --region "${AWS_REGION}"
          '''
        }
      }
    }
  

  post {
    success { echo "✅ Deployed ${env.VERSION} to QA/Prod successfully." }
    failure { echo "❌ Pipeline failed. Check logs above." }
    always  { cleanWs(deleteDirs: true, notFailBuild: true) }
  }

