/// 32-field Alzheimer's risk screening intake form.
/// Submits to POST /patients/{patientId}/risk-screening
/// and returns the result to the caller via onResult callback.
/// Fields from feature_names.json in order, grouped by category.
library;

import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/monad_theme.dart';
import 'risk_screening_card.dart';
import 'monad/monad_pill_button.dart';

class RiskIntakeForm extends StatefulWidget {
  final String patientId;
  final String patientName;
  final void Function(Map<String, dynamic> result) onResult;
  final void Function(RiskScreeningState state, String message)? onFailure;
  const RiskIntakeForm({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.onResult,
    this.onFailure,
  });

  @override
  State<RiskIntakeForm> createState() => _RiskIntakeFormState();
}

class _RiskIntakeFormState extends State<RiskIntakeForm> {
  bool _loading = false;
  String? _error;

  // ── Fields (32 from feature_names.json) ────────────────────────────────
  // Demographic
  final _age = TextEditingController();
  final _gender = TextEditingController(); // 0/1
  final _ethnicity = TextEditingController(); // 0-3
  final _educationLevel = TextEditingController(); // 0-3

  // Physical
  final _bmi = TextEditingController();
  final _systolicBP = TextEditingController();
  final _diastolicBP = TextEditingController();
  final _cholesterolTotal = TextEditingController();
  final _cholesterolLDL = TextEditingController();
  final _cholesterolHDL = TextEditingController();
  final _cholesterolTriglycerides = TextEditingController();

  // Lifestyle
  final _smoking = TextEditingController(); // 0/1
  final _alcoholConsumption = TextEditingController();
  final _physicalActivity = TextEditingController();
  final _dietQuality = TextEditingController();
  final _sleepQuality = TextEditingController();

  // Medical history
  final _familyHistoryAlzheimers = TextEditingController(); // 0/1
  final _cardiovascularDisease = TextEditingController(); // 0/1
  final _diabetes = TextEditingController(); // 0/1
  final _depression = TextEditingController(); // 0/1
  final _headInjury = TextEditingController(); // 0/1
  final _hypertension = TextEditingController(); // 0/1

  // Cognitive / functional
  final _mmse = TextEditingController();
  final _functionalAssessment = TextEditingController();
  final _memoryComplaints = TextEditingController(); // 0/1
  final _behavioralProblems = TextEditingController(); // 0/1
  final _adl = TextEditingController();
  final _confusion = TextEditingController(); // 0/1
  final _disorientation = TextEditingController(); // 0/1
  final _personalityChanges = TextEditingController(); // 0/1
  final _difficultyCompletingTasks = TextEditingController(); // 0/1
  final _forgetfulness = TextEditingController(); // 0/1

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

  /// Submits via [Api.submitRiskScreening] so the request carries the
  /// Authorization header and refresh-retry. Server 401/403/422 details
  /// surface in [_error] via the thrown exception.
  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.submitRiskScreening(
        patientId: widget.patientId,
        payload: _buildPayload(),
      );
      widget.onResult(data);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      final message = error is ApiException
          ? describeApiError(error)
          : 'Screening request failed: $error';
      final state = _stateForError(error);
      widget.onFailure?.call(state, message);
      if (mounted) {
        setState(() {
          _error = message;
          _loading = false;
        });
      }
    }
  }

  RiskScreeningState _stateForError(Object error) {
    if (error is ApiException) {
      if (error.isNetworkError) return RiskScreeningState.transportFailure;
      if (error.statusCode == 403 &&
          error.message.toLowerCase().contains('consent')) {
        return RiskScreeningState.consentRequired;
      }
      if (error.statusCode == 422) return RiskScreeningState.validationFailed;
      if (error.isServerError) return RiskScreeningState.inferenceFailed;
    }
    return RiskScreeningState.transportFailure;
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

    return Dialog(
      child: Container(
        width: 560,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.health_and_safety, color: Monad.indigo, size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text('Cognitive Risk Screening — ${widget.patientName}', style: Monad.subheading)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 4),
            Text(
              '32 clinical inputs. Not a diagnosis — preliminary screening only. '
              'Experimental — not clinically validated.',
              style: Monad.monoCaption,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    Text('MEDICAL HISTORY', style: section),
                    Wrap(spacing: 12, children: [
                      SizedBox(width: 160, child: _field(_familyHistoryAlzheimers, 'Family Hx (0/1)')),
                      SizedBox(width: 160, child: _field(_cardiovascularDisease, 'CVD (0/1)')),
                      SizedBox(width: 120, child: _field(_diabetes, 'Diabetes (0/1)')),
                      SizedBox(width: 120, child: _field(_depression, 'Depression (0/1)')),
                      SizedBox(width: 120, child: _field(_headInjury, 'Head Injury (0/1)')),
                      SizedBox(width: 120, child: _field(_hypertension, 'Hypertension (0/1)')),
                    ]),
                    const SizedBox(height: 16),
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
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: Monad.monoBodySm.copyWith(color: Monad.crimson)),
            ],
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              MonadPillButton(
                label: 'Run Screening',
                onPressed: _submit,
                busy: _loading,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
