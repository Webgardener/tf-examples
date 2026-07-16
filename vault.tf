apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
  annotations:
    pod-policies.kyverno.io/autogen-controllers: none
spec:
  background: true
  rules:
  - name: apcode-and-opscontact
    match:
      any:
      - resources:
          kinds:
          - Service
          - Pod
          - ReplicaSet
          - Deployment
          - StatefulSet
          - DaemonSet
          - Job
          - CronJob
          namespaces: [blue, shared]
    validate:
      failureAction: Audit
      cel:
        expressions:
        - expression: >-
            has(object.metadata.labels)
            && 'apcode' in object.metadata.labels
            && object.metadata.labels['apcode'].matches('^A(P[0-9]{5}|[0-9]{6})$')
          message: "label 'apcode' requis, format APxxxxx ou Axxxxxx."
        - expression: >-
            has(object.metadata.labels)
            && 'opscontact' in object.metadata.labels
            && object.metadata.labels['opscontact'].matches('^[a-zA-Z]+.+[a-zA-Z]+_at_bnpparibas.com$')
          message: "label 'opscontact' requis, format prenom.nom_at_bnpparibas.com."
