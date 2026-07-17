apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-labels
spec:
  validationActions: [Audit]        # → Deny une fois à zéro violation
  evaluation:
    background:
      enabled: true
  autogen:
    podControllers:
      enabled: false                # cf. note ci-dessous — INDISPENSABLE ici
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods, services]
    - apiGroups: [apps]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [deployments, statefulsets, daemonsets, replicasets]
    - apiGroups: [batch]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [jobs, cronjobs]
  variables:
  - name: labels
    expression: "object.metadata.?labels.orValue({})"
  - name: appcode
    expression: "variables.labels[?'appcode'].orValue('')"
  - name: opscontact
    expression: "variables.labels[?'opscontact'].orValue('')"
  validations:
  - expression: "variables.appcode != ''"
    messageExpression: >-
      "label 'appcode' absent sur " + object.kind + "/" + object.metadata.name
  - expression: >-
      variables.appcode == '' || variables.appcode.matches('^A(P[0-9]{5}|[0-9]{6})$')
    messageExpression: >-
      "label 'appcode' mal formé: [" + variables.appcode + "] sur "
      + object.kind + "/" + object.metadata.name + " (attendu APxxxxx ou Axxxxxx)"
  - expression: >-
      variables.opscontact.matches('^[a-zA-Z]+.+[a-zA-Z]+_at_bnpparibas.com$')
    messageExpression: >-
      "label 'opscontact' invalide: [" + variables.opscontact + "] sur "
      + object.kind + "/" + object.metadata.name
