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
        - !variable
          id: <%=role.identifier %>
          annotations:
            provision/provisioner: context
            provision/context/parameter: value
        
        - !permit
          role: !user /<%=role.identifier%>
          resource: !variable <%=role.identifier%>
          privileges: [ read, execute ]

    - !policy edit-template
    - !policy-factory
      id: edit-template
      owner: !user alice
      base: !policy edit-template
      template: |
        - !variable to-be-edited

    - !policy-factory
      id: root-factory
      template: |
        - !variable created-in-root 

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
      "policy_text": "- !variable\n  id: alice\n  annotations:\n    provision/provisioner: context\n    provision/context/parameter: value\n\n- !permit\n  role: !user /alice\n  resource: !variable alice\n  privileges: [ read, execute ]\n",
      "load_to": "certificates",
      "dry_run": true,
      "response": null
    }
    """

  Scenario: Load policy using a factory
    Given I login as "alice"
    And I set the "Content-Type" header to "multipart/form-data; boundary=demo"
    When I successfully POST "/policy_factories/cucumber/certificates" with body from file "policy-factory-context.txt"
    Then the JSON should be:
    """
    {
      "policy_text": "- !variable\n  id: alice\n  annotations:\n    provision/provisioner: context\n    provision/context/parameter: value\n\n- !permit\n  role: !user /alice\n  resource: !variable alice\n  privileges: [ read, execute ]\n",
      "load_to": "certificates",
      "dry_run": false,
      "response": {
        "created_roles": {
        },
        "version": 1
      }
    }
    """
    And I successfully GET "/secrets/cucumber/variable/certificates/alice"
    Then the JSON should be:
    """
    "test value"
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

  Scenario: A policy factory without a base loads into the root policy
    Given I POST "/policy_factories/cucumber/root-factory"
    And the HTTP response status code is 201
    Then I successfully GET "/resources/cucumber/variable/created-in-root"

  Scenario: I retrieve the policy factory template through the API
    Given I login as "alice"
    When I GET "/policy_factories/cucumber/edit-template/template"
    Then the HTTP response status code is 200
    And the JSON response should be:
    """
    {
      "body": "- !variable to-be-edited\n"
    }
    """

  Scenario: I update the policy factory template through the API
    Given I login as "alice"
    When I PUT "/policy_factories/cucumber/edit-template/template" with body:
    """
    - !variable replaced
    """
    Then the HTTP response status code is 202
    When I GET "/policy_factories/cucumber/edit-template/template"
    Then the JSON response should be:
    """
    {
      "body": "- !variable replaced"
    }
    """

  Scenario: I don't have permission to retrieve the policy factory template
    Given I login as "bob"
    When I GET "/policy_factories/cucumber/edit-template/template"
    Then the HTTP response status code is 404
