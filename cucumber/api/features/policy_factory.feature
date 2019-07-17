Feature: Policy Factory

  Background:
    Given I am the super-user
    And I create a new user "alice"
    And I create a new user "bob"
    And I successfully PUT "/policies/cucumber/policy/root" with body:
    """
    - !policy certificates
    - !policy-factory
      id: certificates
      base: !policy certificates
      template: |
        - !variable <%=role.identifier %>

    - !policy annotated-variables
    - !policy-factory
      id: parameterized
      base: !policy annotated-variables
      template: |
        - !variable
          id: <%=role.identifier%>
          annotations:
            description: <%=params[:description]%>

    - !permit
      role: !user bob
      resource: !policy-factory parameterized
      privileges: [ read ]

    - !permit
      role: !user alice
      resource: !policy-factory certificates
      privileges: [ read, execute ]

    - !permit
      role: !user alice
      resource: !policy-factory parameterized
      privileges: [ read, execute ]
    """
    
  Scenario: Dry run loading policy using a factory
    Given I login as "alice"

    When I POST "/policy_factories/cucumber/certificates?dry_run=true"
    Then the JSON should be:
    """
    {
      "policy_text": "- !variable alice\n",
      "load_to": "certificates",
      "dry_run": true,
      "response": null
    }
    """

  Scenario: Load policy using a factory
    Given I login as "alice"

    When I POST "/policy_factories/cucumber/certificates"
    Then the JSON should be:
    """
    {
      "policy_text": "- !variable alice\n",
      "load_to": "certificates",
      "dry_run": false,
      "response": {
        "created_roles": {
        },
        "version": 1
      }
    }
    """

  Scenario: Load parameterized policy using a factory
    Given I login as "alice"

    When I POST "/policy_factories/cucumber/parameterized?description=first%20description"
    Then the JSON should be:
    """
    {
      "policy_text": "- !variable\n  id: alice\n  annotations:\n    description: first description\n",
      "load_to": "annotated-variables",
      "dry_run": false,
      "response": {
        "created_roles": {
        },
        "version": 1
      }
    }
    """

  Scenario: Get a 404 response without read permission
    Given I login as "bob"
    When I POST "/policy_factories/cucumber/certificates"
    Then the HTTP response status code is 404

  Scenario: Get a 403 response without execute permission
    Given I login as "bob"
    When I POST "/policy_factories/cucumber/parameterized"
    Then the HTTP response status code is 403
