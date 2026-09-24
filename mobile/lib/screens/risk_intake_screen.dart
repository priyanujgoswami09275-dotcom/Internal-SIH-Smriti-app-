/// 32-field experimental risk screening intake (mobile).
/// Submits to POST /patients/{patientId}/risk-screening and returns the
/// result via onResult. Field names match feature_names.json / backend
/// RiskScreeningRequest exactly. Not a clinical diagnosis.
library;

import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class RiskIntakeScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final void Function(Map<String, dynamic> result) onResult;
  /// Fired on a 403 whose detail carries 'health_data' (missing consent);
  /// the inline _error text still renders — this only flips the section.
  final VoidCallback? onConsentMissing;
  const RiskIntakeScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.onResult,
    this.onConsentMissing,
  });

  @override
  State<RiskIntakeScreen> createState() => _RiskIntakeScreenState();
}

class _RiskIntakeScreenState extends State<RiskIntakeScreen> {
  final ApiService _api = ApiService.instance;
  bool _loading = false;
  String? _error;

  // Demographic
  final _age = TextEditingController();
  final _gender = TextEditingController();
  final _ethnicity = TextEditingController();
  final _educationLevel = TextEditingController();

  // Physical
  final _bmi = TextEditingController();
  final _systolicBP = TextEditingController();
  final _diastolicBP = TextEditingController();
  final _cholesterolTotal = TextEditingController();
  final _cholesterolLDL = TextEditingController();
  final _cholesterolHDL = TextEditingController();
  final _cholesterolTriglycerides = TextEditingController();

  // Lifestyle
  final _smoking = TextEditingController();
  final _alcoholConsumption = TextEditingController();
  final _physicalActivity = TextEditingController();
  final _dietQuality = TextEditingController();
  final _sleepQuality = TextEditingController();

  // Medical history
  final _familyHistoryAlzheimers = TextEditingController();
  final _cardiovascularDisease = TextEditingController();
  final _diabetes = TextEditingController();
  final _depression = TextEditingController();
  final _headInjury = TextEditingController();
  final _hypertension = TextEditingController();

  // Cognitive / functional
  final _mmse = TextEditingController();
  final _functionalAssessment = TextEditingController();
  final _memoryComplaints = TextEditingController();
  final _behavioralProblems = TextEditingController();
  final _adl = TextEditingController();
  final _confusion = TextEditingController();
  final _disorientation = TextEditingController();
  final _personalityChanges = TextEditingController();
  final _difficultyCompletingTasks = TextEditingController();
  final _forgetfulness = TextEditingController();

  @override
  void dispose() {
    _age.dispose(); _gender.dispose(); _ethnicity.dispose(); _educationLevel.dispose();
    _bmi.dispose(); _systolicBP.dispose(); _diastolicBP.dispose();
    _cholesterolTotal.dispose(); _cholesterolLDL.dispose();
    _cholesterolHDL.dispose(); _cholesterolTriglycerides.dispose();
    _smoking.dispose(); _alcoholConsumption.dispose(); _physicalActivity.dispose();
    _dietQuality.dispose(); _sleepQuality.dispose();
    _familyHistoryAlzheimers.dispose(); _cardiovascularDisease.dispose();
    _diabetes.dispose(); _depression.dispose(); _headInjury.dispose(); _hypertension.dispose();
    _mmse.dispose(); _functionalAssessment.dispose(); _memoryComplaints.dispose();
    _behavioralProblems.dispose(); _adl.dispose(); _confusion.dispose();
    _disorientation.dispose(); _personalityChanges.dispose();
    _difficultyCompletingTasks.dispose(); _forgetfulness.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() => {
    "Age": int.tryParse(_age.text),
    "Gender": int.tryParse(_gender.text),
    "Ethnicity": int.tryParse(_ethnicity.text),
    "EducationLevel": int.tryParse(_educationLevel.text),
    "BMI": double.tryParse(_bmi.text),
    "SystolicBP": int.tryParse(_systolicBP.text),
    "DiastolicBP": int.tryParse(_diastolicBP.text),
    "CholesterolTotal": double.tryParse(_cholesterolTotal.text),
    "CholesterolLDL": double.tryParse(_cholesterolLDL.text),
    "CholesterolHDL": double.tryParse(_cholesterolHDL.text),
    "CholesterolTriglycerides": double.tryParse(_cholesterolTriglycerides.text),
    "Smoking": int.tryParse(_smoking.text),
    "AlcoholConsumption": double.tryParse(_alcoholConsumption.text),
    "PhysicalActivity": double.tryParse(_physicalActivity.text),
    "DietQuality": double.tryParse(_dietQuality.text),
    "SleepQuality": double.tryParse(_sleepQuality.text),
    "FamilyHistoryAlzheimers": int.tryParse(_familyHistoryAlzheimers.text),
    "CardiovascularDisease": int.tryParse(_cardiovascularDisease.text),
    "Diabetes": int.tryParse(_diabetes.text),
    "Depression": int.tryParse(_depression.text),
    "HeadInjury": int.tryParse(_headInjury.text),
    "Hypertension": int.tryParse(_hypertension.text),
    "MMSE": double.tryParse(_mmse.text),
    "FunctionalAssessment": double.tryParse(_functionalAssessment.text),
    "MemoryComplaints": int.tryParse(_memoryComplaints.text),
    "BehavioralProblems": int.tryParse(_behavioralProblems.text),
    "ADL": double.tryParse(_adl.text),
    "Confusion": int.tryParse(_confusion.text),
    "Disorientation": int.tryParse(_disorientation.text),
    "PersonalityChanges": int.tryParse(_personalityChanges.text),
    "DifficultyCompletingTasks": int.tryParse(_difficultyCompletingTasks.text),
    "Forgetfulness": int.tryParse(_forgetfulness.text),
  };

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.submitRiskScreening(
          patientId: widget.patientId, payload: _buildPayload());
      developer.log('risk screening status=${data['status']}', name: 'RiskIntake');
      widget.onResult(data);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // Backend detail ('Active consent required for scope health_data')
      // flows into ApiException.message via _decode's `detail` field.
      if (e.statusCode == 403 && e.message.contains('health_data')) {
        widget.onConsentMissing?.call();
      }
      if (mounted) {
        setState(() {
          _error = e.statusCode == 403
              ? 'Not permitted (clinical tier + health-data consent required). ${e.message}'
              : e.message;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Widget _field(TextEditingController ctrl, String label, {String? hint}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, hintText: hint ?? '', isDense: true),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    );

  @override
  Widget build(BuildContext context) {
    const section = TextStyle(fontFamily: Monad.monoFamily, fontSize: 12,
        letterSpacing: -0.4, color: Monad.smoke, fontWeight: FontWeight.w500);

    return Scaffold(
      appBar: AppBar(
        title: Text('Risk screening', style: Monad.subheading),
        backgroundColor: Monad.parchment,
      ),
      backgroundColor: Monad.parchment,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('32 clinical inputs · ${widget.patientName}',
                      style: Monad.monoBody),
                  const SizedBox(height: 4),
                  Text(
                    'Not a diagnosis — preliminary screening only. Experimental / not clinically validated.',
                    style: Monad.monoCaption.copyWith(color: Monad.terracotta),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DEMOGRAPHIC', style: section),
                    _field(_age, 'Age (60-90)'),
                    Row(children: [
                      Expanded(child: _field(_gender, 'Gender (0=F, 1=M)')),
                      Expanded(child: _field(_ethnicity, 'Ethnicity (0-3)')),
                    ]),
                    _field(_educationLevel, 'Education Level (0-3)'),
                    const SizedBox(height: 12),
                    Text('PHYSICAL MEASUREMENTS', style: section),
                    Row(children: [
                      Expanded(child: _field(_bmi, 'BMI')),
                      Expanded(child: _field(_systolicBP, 'Systolic BP')),
                      Expanded(child: _field(_diastolicBP, 'Diastolic BP')),
                    ]),
                    Row(children: [
                      Expanded(child: _field(_cholesterolTotal, 'Total Chol.')),
                      Expanded(child: _field(_cholesterolLDL, 'LDL')),
                      Expanded(child: _field(_cholesterolHDL, 'HDL')),
                    ]),
                    _field(_cholesterolTriglycerides, 'Triglycerides'),
                    const SizedBox(height: 12),
                    Text('LIFESTYLE', style: section),
                    Row(children: [
                      Expanded(child: _field(_smoking, 'Smoking (0/1)')),
                      Expanded(child: _field(_alcoholConsumption, 'Alcohol (0-20)')),
                    ]),
                    Row(children: [
                      Expanded(child: _field(_physicalActivity, 'Physical Activity (0-10)')),
                      Expanded(child: _field(_dietQuality, 'Diet Quality (0-10)')),
                      Expanded(child: _field(_sleepQuality, 'Sleep Quality (4-10)')),
                    ]),
                    const SizedBox(height: 12),
                    Text('MEDICAL HISTORY', style: section),
                    Wrap(spacing: 12, children: [
                      SizedBox(width: 160, child: _field(_familyHistoryAlzheimers, 'Family Hx (0/1)')),
                      SizedBox(width: 160, child: _field(_cardiovascularDisease, 'CVD (0/1)')),
                      SizedBox(width: 120, child: _field(_diabetes, 'Diabetes (0/1)')),
                      SizedBox(width: 120, child: _field(_depression, 'Depression (0/1)')),
                      SizedBox(width: 120, child: _field(_headInjury, 'Head Injury (0/1)')),
                      SizedBox(width: 120, child: _field(_hypertension, 'Hypertension (0/1)')),
                    ]),
                    const SizedBox(height: 12),
                    Text('COGNITIVE & FUNCTIONAL', style: section),
                    Row(children: [
                      Expanded(child: _field(_mmse, 'MMSE (0-30)')),
                      Expanded(child: _field(_functionalAssessment, 'Functional Assess.')),
                      Expanded(child: _field(_adl, 'ADL')),
                    ]),
                    Wrap(spacing: 12, children: [
                      SizedBox(width: 160, child: _field(_memoryComplaints, 'Memory Complaints (0/1)')),
                      SizedBox(width: 160, child: _field(_behavioralProblems, 'Behavioral Problems (0/1)')),
                      SizedBox(width: 120, child: _field(_confusion, 'Confusion (0/1)')),
                      SizedBox(width: 120, child: _field(_disorientation, 'Disorientation (0/1)')),
                      SizedBox(width: 160, child: _field(_personalityChanges, 'Personality Changes (0/1)')),
                      SizedBox(width: 200, child: _field(_difficultyCompletingTasks, 'Difficulty Tasks (0/1)')),
                      SizedBox(width: 140, child: _field(_forgetfulness, 'Forgetfulness (0/1)')),
                    ]),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(_error!,
                    style: Monad.monoBodySm.copyWith(color: Monad.crimson)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                MonadPillButton(label: 'Run Screening', onPressed: _submit, busy: _loading),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
