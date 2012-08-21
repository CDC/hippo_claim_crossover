require 'ruby_claim'
require 'hippo'
require 'pry'

class HippoClaimCrossover
  def initialize(string)
    @hippo_object ||= Hippo::TransactionSets::HIPAA_837::L2000A.new.parse(string)
    @claim        ||= RubyClaim::Claim.new(:hide_background=>false)
  end

  def claim
    return @claim
  end

  def to_claim
    claim.insurance_type = :medicare
    claim.patient_or_authorized_signature          = "Signature on File"
    claim.patient_or_authorized_signature_date     = "2012-08-02"                # Field type is string, not date!
    claim.insured_or_authorized_signature          = "Signature on File"

    @hippo_object.L2000B do |l2000b|

      l2000b.L2010BB do |l2010bb|
        claim.carrier_name      = l2010bb.NM1.NameLastOrOrganizationName
        claim.carrier_address_1 = l2010bb.N3.AddressInformation

        l2010bb.N4 do |n4|
          claim.carrier_city  =  n4.CityName
          claim.carrier_state =  n4.StateOrProvinceCode
          claim.carrier_zip   =  n4.PostalCode
        end

        l2010bb.REF_01 do |ref|
          claim.insured_id_number = ref.ReferenceIdentification
        end
      end

      l2000b.L2010BA do |l2010ba|
        claim.insured_name = l2010ba.NM1.NameLastOrOrganizationName
        claim.carrier_address_1 = l2010ba.N3.AddressInformation

        l2010ba.N4 do |n4|
          claim.insured_city  =  n4.CityName
          claim.insured_state =  n4.StateOrProvinceCode
          claim.insured_zip   =  n4.PostalCode
        end
      end

      if patient_is_subscriber?
        l2000b.L2010BA {|l2010ba| populate_patient(l2010ba)}
      else
        l2000b.L2000C.L2010CA {|l2010ca| populate_patient(l2010ca)}
      end

      l2000b.L2300.L2310C do |l2310c|
        claim.service_facility_name    = l2310c.NM1.NameLastOrOrganizationName
        claim.service_facility_address = l2310c.N3.AddressInformation

        l2310c.N4 do |n4|
          claim.service_facility_city  =  n4.CityName
          claim.service_facility_state =  n4.StateOrProvinceCode
          claim.service_facility_zip   =  n4.PostalCode
        end
      end

      claim.referring_provider_name = l2000b.L2300.L2310A.NM1.NameLastOrOrganizationName
    end # L2000B




    # claim.referring_provider_name                  = "Other Source or Provider"
    claim.referring_provider_npi                   = "12031021230"
    claim.referring_provder_other_identifier       = "J1"
    claim.referring_provider_other_number          = "10000000000002"

    claim.insured_phone                            = '3525555555'

    claim.insured_employer_or_school_name          = 'University of Central London'
    claim.insured_other_health_benefit_plan_exists = false
    claim.insured_policy_or_group_number           = '12341251'
    claim.insured_date_of_birth                    = '1947-11-04'
    claim.insured_sex                              = :male
    claim.insured_insurance_plan_or_program_name   = "Blue Cross Bad Wolf"

    claim.other_insured_name                       = 'Flinstone, Frederick, C'
    claim.other_insured_sex                        = :male
    claim.other_insured_date_of_birth              = '1955-10-31'
    claim.other_insured_policy_or_group_number     = '123451'
    claim.employer_name_or_school_name             = 'University Of Florida'
    claim.other_insured_plan_or_program_name       = 'PLAN OR PROGRAM NAME'


    # claim.patient_name                             = "Jane Jetson"
    # claim.patient_address                          = 'patient_address'
    # claim.patient_date_of_birth                    = '1960-07-21'
    # claim.patient_sex                              = :female
    # claim.patient_city                             = 'Ocala'
    # claim.patient_state                            = 'FL'
    # claim.patient_zip                              = '34476'
    claim.patient_phone                            = '3525555555'
    claim.patient_marital_status                   = :single
    claim.patient_employment_status                = :full_time_student
    claim.patient_relationship_to_insured          = :self

    claim.condition_related_to_other_accident      = true
    claim.condition_related_to_employment          = false
    claim.condition_related_to_auto_accident       = false
    claim.condition_place                          = "FL"

    claim.condition_reserved_for_local_use         = "RESERVED FOR LOCAL"
    # Section 14 and lower

    claim.incident_date                            = "2012-02-03"
    claim.incident_onset_date                      = "2012-02-10"

    claim.dates_unable_to_work_from                = "2012-02-10"
    claim.dates_unable_to_work_to                  = "2012-02-11"



    claim.admit_date                               = "2012-02-10"
    claim.discharge_date                           = "2012-02-14"
    claim.reserved_for_local_use                   = "Reserved for future use"
    claim.outside_lab                              = true                       #20
    claim.outside_lab_charges                      = 999999.01                  #20

    # 21
    claim.set_diagnosis_code(1, 'V722.83')
    claim.set_diagnosis_code(2, '720.2')
    claim.set_diagnosis_code(3, '100.2')
    claim.set_diagnosis_code(4, '100.2')

    claim.medicaid_resubmission_code               = 'MRC-1'
    claim.medicaid_resubmission_orginal_ref_number = 'probably unused'
    claim.prior_authorization_number               = '100000000020310'
    claim.federal_tax_id                           = :ssn
    claim.patient_account_number                   = '999999999999999'
    claim.accepts_assignment                       = false

    claim.total_charge                             = 200.01
    claim.amount_paid                              = 201.99
    claim.balance_due                              = -1.99

    claim.provider_signature                       = "Physician Signature"
    claim.provider_signature_date                  = "2012-01-02"           # String not date field object

    # claim.service_facility_name                    = "Service or Facility Name - OR"
    # claim.service_facility_address                 = "12345 Example Rd"
    # claim.service_facility_city                    = "Miami"
    # claim.service_facility_state                   = "FL"
    # claim.service_facility_zip                     = "34476"
    claim.service_facility_npi                     = "10000000000"
    claim.service_facility_legacy_number           = "10000000000"

    claim.billing_provider_name                    = "North Shore ANES Partners"
    claim.billing_provider_address                 = "12345 Example Rd"
    claim.billing_provider_city                    = "Miami"
    claim.billing_provider_state                   = "FL"
    claim.billing_provider_zip                     = "34476"
    claim.billing_provider_phone                   = "5555555555"
    claim.billing_provider_npi                     = "10000000000"
    claim.billing_provider_legacy_number           = "10000000000"

    (0...6).each do |i|
      claim.build_service do |s|
        s.date_of_service_from    = claim.time_rand
        s.date_of_service_to      = claim.time_rand
        s.place_of_service        = "22"
        s.emergency               = "12"
        s.procedure_code          = "00851"
        s.modifier_1              = "10"
        s.modifier_2              = "10"
        s.modifier_3              = "10"
        s.modifier_4              = "10"
        s.diagnosis_pointer       = "1"
        s.charges                 = 200.10
        s.days_or_units           = 20
        s.epsdt_family_plan       = "Y"
        s.npi_number              = rand(10000000000000).to_s
        s.legacy_number_qualifier = "J1"
        s.legacy_number           = rand(10000000000000).to_s
        s.description             = "START: 8:20AM      END: 9:12AM      MINUTES: 52 (Whatever you want!)"
      end
    end
    return claim
  end

  def populate_patient(parent)
    parent.NM1 do |nm1|
      claim.patient_name = nm1.NameLastOrOrganizationName
    end

    parent.N3 do |n3|
      claim.patient_address = n3.AddressInformation
    end

    parent.N4 do |n4|
      claim.patient_city  =  n4.CityName
      claim.patient_state =  n4.StateOrProvinceCode
      claim.patient_zip   =  n4.PostalCode
    end

    parent.DMG do |dmg|
      claim.patient_date_of_birth = [[0,4],[4,2],[6,2]].map {|pos| dmg.DateTimePeriod[*pos] }.join("-")
      claim.patient_sex           = (dmg.GenderCode == "M") ? :male : :female
    end
  end

  def patient_is_subscriber?
    @hippo_object.L2000B.HL.HierarchicalChildCode == "0"
  end
end


if  __FILE__ == $0
  hcc = HippoClaimCrossover.new(File.read("./sample_claim/example.txt"))

  claim = hcc.to_claim
  claim.to_pdf("/Users/jjackson/Desktop/test.pdf")

  `open /Users/jjackson/Desktop/test.pdf`
end