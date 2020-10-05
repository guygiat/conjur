Feature: A permitted Conjur host can login with a valid resource restrictions
  that is defined in the id

  Scenario: Login as a Deployment.
    Then I can login to authn-k8s as "deployment/inventory-deployment"
