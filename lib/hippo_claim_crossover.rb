require 'ruby_claim'
require 'hippo'
require 'pry'

class HippoClaimCrossover
  VERSION = '0.0.1'

  attr_reader :claim

  def initialize(string)
    @hippo_object ||= Hippo::TransactionSets::HIPAA_837::L2000A.new.parse(string)
    @claim        ||= RubyClaim::Claim.new(:hide_background => false)
  end

  def to_claim
    populate_billing_provider(@hippo_object.L2010AA)
    populate_subscriber(@hippo_object.L2000B)

    return claim
  end

  def populate_billing_provider(l2010aa)
    claim.billing_provider_name                    = get_name(l2010aa.NM1) #33
    claim.billing_provider_npi                     = l2010aa.NM1.IdentificationCode #33a
    claim.billing_provider_address                 = l2010aa.N3.AddressInformation #33b

    l2010aa.N4 do |n4|
      claim.billing_provider_city  =  n4.CityName #33
      claim.billing_provider_state =  n4.StateOrProvinceCode #33
      claim.billing_provider_zip   =  n4.PostalCode #33
    end

    #25
    l2010aa.find_by_name('Billing Provider Tax Identification') do |ref|
      claim.federal_tax_id_type = if ref.ReferenceIdentificationQualifier == 'SY'
                                    :ssn
                                  else
                                    :ein
                                  end
      claim.federal_tax_id      = ref.ReferenceIdentification
    end

    per = l2010aa.PER.detect{|s| s.CommunicationNumberQualifier == 'TE' }

    claim.billing_provider_phone = per.CommunicationNumber if per
  end

  def populate_subscriber(l2000b)
    binding.pry
    l2000b.L2010BB do |l2010bb|
      claim.carrier_name      = l2010bb.NM1.NameLastOrOrganizationName  #carrier_block
      claim.carrier_address_1 = l2010bb.N3.AddressInformation  #carrier_block

      l2010bb.N4 do |n4|
        claim.carrier_city  =  n4.CityName #carrier_block
        claim.carrier_state =  n4.StateOrProvinceCode #carrier_block
        claim.carrier_zip   =  n4.PostalCode #carrier_block
      end

    end

    claim.insurance_type =  case l2000b.SBR.ClaimFilingIndicatorCode #1
                            when 'MA','MB'  then :medicare
                            when 'MC'       then :medicaid
                            when 'CH'       then :champus
                            when 'VA'       then :champva
                            else                 :other
                            end

    # insured
    l2000b.L2010BA do |l2010ba|
      claim.insured_name      = get_name(l2010ba.NM1) #4
      claim.insured_address   = l2010ba.N3.AddressInformation #7
      claim.insured_id_number = l2010ba.NM1.IdentificationCode #1a

      l2010ba.N4 do |n4|
        claim.insured_city  =  n4.CityName            #7
        claim.insured_state =  n4.StateOrProvinceCode #7
        claim.insured_zip   =  n4.PostalCode          #7
      end

      l2010ba.DMG do |dmg|
        claim.insured_date_of_birth = parse_dmg_date(dmg) #11a
        claim.insured_sex           = parse_dmg_dob(dmg) #11a
      end
    end

    # other insured
    l2000b.L2300.L2320.L2330A do |l2330a|
      claim.other_insured_name = get_name(l2330a.NM1) #9
    end

    claim.insured_insurance_plan_or_program_name = l2000b.SBR.Name #11c
    claim.insured_policy_or_group_number         = l2000b.SBR.ReferenceIdentification

    if patient_is_subscriber?
      claim.patient_relationship_to_insured = :self #6
      l2000b.L2010BA {|l2010ba| populate_patient(l2010ba)}
      populate_claim(l2000b.L2300)
    else
      claim.patient_relationship_to_insured = get_relationship(l2000b.L2000C.PAT.IndividualRelationshipCode) #6
      l2000b.L2000C.L2010CA {|l2010ca| populate_patient(l2010ca)}
      populate_claim(l2000b.L2000C.L2300)
    end
  end

  def populate_claim(claim_loop)
    # Claim Loop
    claim_loop.each do |l2300|
      claim.provider_signature_date                  = Date.today.to_s
      claim.insured_or_authorized_signature          = "Signature on File"
      claim.patient_or_authorized_signature          = "Signature on File"
      claim.patient_or_authorized_signature_date     = l2300.L2400.DTP.DateTimePeriod.to_s
      claim.insured_other_health_benefit_plan_exists = l2300.L2320.length > 0 #11d
      claim.other_insured_policy_or_group_number     = l2300.L2320.SBR.ReferenceIdentification #9a
      claim.other_insured_plan_or_program_name       = l2300.L2320.SBR.Name  #9d
      claim.condition_reserved_for_local_use         = l2300.NTE.Description
      claim.incident_date                            = l2300.find_by_name('Date - Accident').DateTimePeriod.to_s
      claim.admit_date                               = l2300.find_by_name('Date - Admission').DateTimePeriod.to_s
      claim.discharge_date                           = l2300.find_by_name('Date - Discharge').DateTimePeriod.to_s
      claim.prior_authorization_number               = l2300.REF.ReferenceIdentification #23
      claim.patient_account_number                   = l2300.CLM.ClaimSubmitterSIdentifier #26
      claim.accepts_assignment                       = l2300.CLM.ProviderAcceptAssignmentCode == "A" #27
      claim.provider_signature                       = l2300.CLM.YesNoConditionOrResponseCode == "Y" ? "Signature on File" : "" #31

      l2300.find_by_name('Date - Disability Dates') do |dtp|
        next if dtp.DateTimePeriod.nil?

        tmp = case dtp.DateTimeQualifier
              when "314"
                [dtp.DateTimePeriod.first,dtp.DateTimePeriod.last]
              when "360"
                [dtp.DateTimePeriod, nil]
              when "361"
                [nil, dtp.DateTimePeriod]
              end

        claim.dates_unable_to_work_from,claim.dates_unable_to_work_to = tmp #16
      end

      claim.set_diagnosis_code(1, format_diagnosis_code(l2300.HI.IndustryCode_01)) #21
      claim.set_diagnosis_code(2, format_diagnosis_code(l2300.HI.IndustryCode_02)) #21
      claim.set_diagnosis_code(3, format_diagnosis_code(l2300.HI.IndustryCode_03)) #21
      claim.set_diagnosis_code(4, format_diagnosis_code(l2300.HI.IndustryCode_04)) #21

      set_patient_condition_related_to(l2300.CLM) #10a

      l2300.L2310A do |l2310a|
        claim.referring_provider_name             = get_name(l2310a.NM1) #17
        claim.referring_provider_npi              = l2310a.NM1.IdentificationCode #17b
        claim.referring_provder_other_identifier  = l2310a.REF.ReferenceIdentificationQualifier #17a
        claim.referring_provider_other_number     = l2310a.REF.ReferenceIdentification #17a
      end

      l2300.L2310C do |l2310c|
        claim.service_facility_npi     = l2310c.NM1.IdentificationCode #32a
        claim.service_facility_name    = get_name(l2310c.NM1)
        claim.service_facility_address = l2310c.N3.AddressInformation #32

        l2310c.N4 do |n4|
          claim.service_facility_city  =  n4.CityName            #32
          claim.service_facility_state =  n4.StateOrProvinceCode #32
          claim.service_facility_zip   =  n4.PostalCode          #32
        end
      end


      populate_services(l2300.L2400) #24
    end
  end

  def format_diagnosis_code(code)
    #     Standard codes have Decimal place XXX.XX
    #     Some Codes Do not have trailing decimal places
    #     V Codes also follow the XXX.XX format --> V54.31
    #     E Codes follow XXXX.X --> E850.9
    return if code.nil?
    if code  =~ /\AE/
      code.insert(4,'.')
    else
      code.insert(3,'.')
    end
  end

  def populate_services(service_loop)
    service_loop.each do |srv|
      claim.build_service do |s|
        s.date_of_service_from                    = srv.DTP.DateTimePeriod.to_s
        s.place_of_service                        = get_place_of_service_identifier(srv)
        s.emergency                               = ''
        s.procedure_code                          = srv.L2430.SVD.ProductServiceId
        s.modifier_1                              = srv.L2430.SVD.ProcedureModifier_01
        s.modifier_2                              = srv.L2430.SVD.ProcedureModifier_02
        s.modifier_3                              = srv.L2430.SVD.ProcedureModifier_03
        s.modifier_4                              = srv.L2430.SVD.ProcedureModifier_04
        s.diagnosis_pointer                       = [srv.SV1.DiagnosisCodePointer_01,srv.SV1.DiagnosisCodePointer_02,srv.SV1.DiagnosisCodePointer_03,srv.SV1.DiagnosisCodePointer_04].join
        s.charges                                 = srv.SV1.MonetaryAmount.to_f
        s.days_or_units                           = srv.L2430.SVD.Quantity.to_i
        s.epsdt_family_plan                       = ''
        s.npi_number                              = get_service_npi(srv)
        s.legacy_number_qualifier,s.legacy_number = get_service_legacy_number_qualifier_and_legacy_number(srv)
        s.description                             = srv.SV1.Description
      end
    end
    claim.outside_lab_charges                      = service_loop.inject(0.0)   {|m,v| m += v.PS1.MonetaryAmount.to_f; m} #20
    claim.outside_lab                              = !!claim.outside_lab_charges

    claim.total_charge                             = claim.services.inject(0.0) {|m,s| m += s.charges; m} #28
    claim.amount_paid                              = service_loop.inject(0.0)   {|m,v| m += v.L2430.SVD.MonetaryAmount.to_f; m} #29
    claim.balance_due                              = claim.total_charge - claim.amount_paid #30
  end

  def set_patient_condition_related_to(claim_loop)
    claim.condition_related_to_other_accident = claim_loop.RelatedCausesCode_01 == "OA" || claim_loop.RelatedCausesCode_02
    claim.condition_related_to_employment     = claim_loop.RelatedCausesCode_01 == "EM" || claim_loop.RelatedCausesCode_02
    claim.condition_related_to_auto_accident  = claim_loop.RelatedCausesCode_01 == "AA" || claim_loop.RelatedCausesCode_02
    claim.condition_place                     = claim_loop.StateOrProvinceCode
  end

  def get_name(nm1)
    if nm1.EntityTypeQualifier == '1'
      "#{nm1.NameLastOrOrganizationName.to_s}, #{nm1.NameFirst.to_s}#{', ' + nm1.NameMiddle[0,1] if nm1.NameMiddle}"
    else
      nm1.NameLastOrOrganizationName
    end
  end

  def get_relationship(relationship)
    case relationship
    when "01" then :spouse
    when "19" then :child
    else           :other
    end
  end

  def get_place_of_service_identifier(service)
    if service.SV1.FacilityCodeValue.nil?
       @hippo_object.L2000B.L2300.CLM.FacilityCodeValue
    else
      service.SV1.FacilityCodeValue
    end
  end

  def get_service_legacy_number_qualifier_and_legacy_number(service)
    if !service.L2420A.REF.ReferenceIdentification.nil?
      [service.L2420A.REF.ReferenceIdentificationQualifier,
      service.L2420A.REF.ReferenceIdentification]
    elsif !service.L2420A.PRV.ReferenceIdentification.nil?
      ['ZZ',
       service.L2420A.PRV.ReferenceIdentification]
    elsif !@hippo_object.L2000B.L2300.L2310B.REF.ReferenceIdentification.nil?
      [@hippo_object.L2000B.L2300.L2310B.REF.ReferenceIdentificationQualifier,
       @hippo_object.L2000B.L2300.L2310B.REF.ReferenceIdentification ]
    else
      ['ZZ',
       @hippo_object.L2000B.L2300.L2310B.PRV.ReferenceIdentification ]
    end
  end

  def get_service_npi(service)
    if service.L2420A.NM1.IdentificationCode.nil?
      @hippo_object.L2000B.L2300.L2310A.NM1.IdentificationCode
    else
      service.L2420A.NM1.IdentificationCode
    end
  end

  def populate_patient(parent)
    parent.NM1 do |nm1|
      claim.patient_name = get_name(nm1) #2
    end

    parent.N3 do |n3|
      claim.patient_address = n3.AddressInformation #5
    end

    parent.N4 do |n4|
      claim.patient_city  =  n4.CityName             #5
      claim.patient_state =  n4.StateOrProvinceCode  #5
      claim.patient_zip   =  n4.PostalCode           #5
    end

    parent.DMG do |dmg|
      claim.patient_date_of_birth = parse_dmg_date(dmg) #3
      claim.patient_sex           = (dmg.GenderCode == "M") ? :male : :female #3
    end
  end

  def patient_is_subscriber?
    @hippo_object.L2000B.HL.HierarchicalChildCode == "0"
  end

  def parse_dmg_date(dmg)
    dmg.DateTimePeriod.to_s
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
