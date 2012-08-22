require 'ruby_claim'
require 'hippo'

class HippoClaimCrossover
  VERSION = '0.0.1'

  attr_reader :claim

  def initialize(string)
    @hippo_object ||= Hippo::TransactionSets::HIPAA_837::L2000A.new.parse(string)
    @claim        ||= RubyClaim::Claim.new(:hide_background=>false)
  end

  def to_claim
    claim.insurance_type                           = :medicare
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

      # insured
      l2000b.L2010BA do |l2010ba|
        claim.insured_name = l2010ba.NM1.NameLastOrOrganizationName
        claim.carrier_address_1 = l2010ba.N3.AddressInformation

        l2010ba.N4 do |n4|
          claim.insured_city  =  n4.CityName
          claim.insured_state =  n4.StateOrProvinceCode
          claim.insured_zip   =  n4.PostalCode
        end

        l2010ba.DMG do |dmg|
          claim.insured_date_of_birth                    = parse_dmg_date(dmg)
          claim.insured_sex                              = parse_dmg_dob(dmg)
        end
      end

      # other insured
      l2000b.L2300.L2320.L2330A do |l2330a|
        claim.other_insured_name = l2330a.NM1.NameLastOrOrganizationName
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

      l2000b.L2300.L2310A do |l2310a|
        claim.referring_provider_name             = l2310a.NM1.NameLastOrOrganizationName
        claim.referring_provider_npi              = l2310a.NM1.IdentificationCode
        claim.referring_provder_other_identifier  = l2310a.REF.ReferenceIdentificationQualifier
        claim.referring_provider_other_number     = l2310a.REF.ReferenceIdentification
      end

      populate_services(l2000b.L2300.L2400)
    end # L2000B



    claim.employer_name_or_school_name             = 'University Of Florida'

    claim.insured_policy_or_group_number           = '12341251'
    claim.insured_other_health_benefit_plan_exists = false
    claim.insured_employer_or_school_name          = 'University of Central London'
    claim.insured_insurance_plan_or_program_name   = "Blue Cross Bad Wolf"


    claim.other_insured_date_of_birth              = "2010-01-01"
    claim.other_insured_sex                        = :male
    claim.other_insured_policy_or_group_number     = '123451'

    claim.other_insured_plan_or_program_name       = 'PLAN OR PROGRAM NAME'

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


    return claim
  end

  def populate_services(service_loop)
    service_loop.each do |srv|
      claim.build_service do |s|
        binding.pry

        s.date_of_service_from    = [[0,4],[4,2],[6,2]].map {|pos| srv.DTP.DateTimePeriod[*pos]}.join("-")
        s.place_of_service        = "22"
        s.emergency               = ''
        s.procedure_code          = srv.L2430.SVD.ProductServiceId
        s.modifier_1              = srv.L2430.SVD.ProcedureModifier_01
        s.modifier_2              = srv.L2430.SVD.ProcedureModifier_02
        s.modifier_3              = srv.L2430.SVD.ProcedureModifier_03
        s.modifier_4              = srv.L2430.SVD.ProcedureModifier_04
        s.diagnosis_pointer       = "1"
        s.charges                 = srv.L2430.SVD.MonetaryAmount.to_f
        s.days_or_units           = srv.L2430.SVD.Quantity.to_i
        s.epsdt_family_plan       = "Y"
        s.npi_number              = rand(10000000000000).to_s
        s.legacy_number_qualifier = "J1"
        s.legacy_number           = rand(10000000000000).to_s
        s.description             = ""
      end
    end
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
      claim.patient_date_of_birth = parse_dmg_date(dmg)
      claim.patient_sex           = (dmg.GenderCode == "M") ? :male : :female
    end
  end

  def patient_is_subscriber?
    @hippo_object.L2000B.HL.HierarchicalChildCode == "0"
  end

  def parse_dmg_date(dmg)
    [[0,4],[4,2],[6,2]].map {|pos| dmg.DateTimePeriod[*pos] }.join("-")
  end

  def parse_dmg_dob(dmg)
    (dmg.GenderCode == "M") ? :male : :female
  end
end


if  __FILE__ == $0
  hcc = HippoClaimCrossover.new(File.read("./sample_claim/example.txt"))

  claim = hcc.to_claim
  claim.to_pdf("/Users/jjackson/Desktop/test.pdf")

  `open /Users/jjackson/Desktop/test.pdf`
end