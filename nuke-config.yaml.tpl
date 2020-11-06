regions:
  - ap-northeast-1
  - global

account-blacklist:
  - 999999999999 # 必須パラメータなのでダミーを登録しておく

resource-types:
  excludes:
    - IAMGroup
    - IAMGroupPolicyAttachment
    - IAMLoginProfile
    - IAMPolicy
    - IAMRole
    - IAMRolePolicy
    - IAMRolePolicyAttachment
    - IAMUser
    - IAMUserAccessKey
    - IAMUserGroupAttachment
    - IAMVirtualMFADevice
    - Route53HostedZone

accounts:
  ${account_id}: # 該当のAWSアカウントIDを指定する
    filters:
      CloudWatchEventsRule:
        - "Rule: ${cloudwatch_events_rule_name}"
      CloudWatchEventsTarget:
        - type: glob
          value: "Rule: ${cloudwatch_events_rule_name}*"
      CloudWatchLogsLogGroup:
        - "${cloudwatch_log_group_name}"
      CodeBuildProject:
        - type: glob
          value: "${codebuild_project_name}*"
      S3Bucket:
        - "s3://${s3_bucket_name}"
      S3Object:
        - property: Bucket
          type: glob
          value: "${s3_bucket_name}*"
