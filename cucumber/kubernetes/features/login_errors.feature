Feature: Errors emitted by the login method.

  @ssl_dir_perm
  Scenario: Cert injection errors are written to a file in the client container
    Given I make ssl dir non-writable in container "authenticator" of pod matching "app=inventory-pod"
    When I login to pod matching "app=inventory-pod" to authn-k8s as "*/*"
    Then the cert injection logs exist in the client container