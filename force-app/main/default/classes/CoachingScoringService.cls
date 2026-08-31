public class CoachingScoringService {

    public class ScoreResult {
        public Decimal managerTotalScore;
        public Decimal employeeTotalScore;
        public String sectionScoresJson;
        public String recommendedActionPlan;
    }

    public static ScoreResult computeScores(String templateJson, String responsesJson) {
        ScoreResult result = new ScoreResult();
        result.managerTotalScore = 0;
        result.employeeTotalScore = 0;
        result.sectionScoresJson = '{}';

        if (String.isBlank(templateJson)) {
            return result;
        }

        Map<String, Object> template = (Map<String, Object>) JSON.deserializeUntyped(templateJson);
        List<Object> questions = (List<Object>) template.get('questions');
        if (questions == null || questions.isEmpty()) {
            return result;
        }

        Map<String, Object> responsesByQuestion = buildResponseMap(responsesJson);

        Decimal managerEarned = 0;
        Decimal employeeEarned = 0;
        Decimal totalMax = 0;

        Map<String, Map<String, Object>> sectionAggregates = new Map<String, Map<String, Object>>();

        for (Object qObj : questions) {
            Map<String, Object> question = (Map<String, Object>) qObj;
            String type = (String) question.get('type');
            if (type != 'scale') {
                continue;
            }

            String questionId = (String) question.get('id');
            String section = String.isNotBlank((String) question.get('section'))
                ? (String) question.get('section')
                : 'General';
            String questionLabel = (String) question.get('question');
            Decimal maxPoints = getQuestionMaxPoints(question);

            totalMax += maxPoints;

            Map<String, Object> response = (Map<String, Object>) responsesByQuestion.get(questionId);
            Decimal managerScore = getScaleScore(question, response, 'managerValue');
            Decimal employeeScore = getScaleScore(question, response, 'employeeValue');

            managerEarned += managerScore;
            employeeEarned += employeeScore;

            if (!sectionAggregates.containsKey(section)) {
                sectionAggregates.put(section, initSectionAggregate());
            }
            Map<String, Object> sectionData = sectionAggregates.get(section);
            sectionData.put('managerEarned', (Decimal) sectionData.get('managerEarned') + managerScore);
            sectionData.put('employeeEarned', (Decimal) sectionData.get('employeeEarned') + employeeScore);
            sectionData.put('maxPoints', (Decimal) sectionData.get('maxPoints') + maxPoints);

            if (maxPoints > 0) {
                Decimal ratio = managerScore / maxPoints;
                List<Object> strengths = (List<Object>) sectionData.get('strengths');
                List<Object> weaknesses = (List<Object>) sectionData.get('weaknesses');
                if (ratio >= 0.80) {
                    strengths.add(questionLabel);
                } else if (ratio < 0.50) {
                    weaknesses.add(questionLabel);
                }
            }

            if (response != null) {
                Object managerValObj = response.get('managerValue');
                Object employeeValObj = response.get('employeeValue');
                if (managerValObj != null && employeeValObj != null) {
                    Integer managerVal = Integer.valueOf(String.valueOf(managerValObj));
                    Integer employeeVal = Integer.valueOf(String.valueOf(employeeValObj));
                    if (Math.abs(managerVal - employeeVal) >= 2) {
                        List<Object> gaps = (List<Object>) sectionData.get('gaps');
                        gaps.add(new Map<String, Object>{
                            'question' => questionLabel,
                            'managerScore' => managerVal,
                            'employeeScore' => employeeVal,
                            'delta' => Math.abs(managerVal - employeeVal)
                        });
                    }
                }
            }
        }

        if (totalMax > 0) {
            result.managerTotalScore = ((managerEarned / totalMax) * 100).setScale(2);
            result.employeeTotalScore = ((employeeEarned / totalMax) * 100).setScale(2);
        }

        Map<String, Object> sectionOutput = new Map<String, Object>();
        for (String sectionName : sectionAggregates.keySet()) {
            Map<String, Object> agg = sectionAggregates.get(sectionName);
            Decimal sectionMax = (Decimal) agg.get('maxPoints');
            Map<String, Object> sectionResult = new Map<String, Object>();
            sectionResult.put('maxScore', 100);
            if (sectionMax > 0) {
                sectionResult.put(
                    'managerScore',
                    (((Decimal) agg.get('managerEarned') / sectionMax) * 100).setScale(1)
                );
                sectionResult.put(
                    'employeeScore',
                    (((Decimal) agg.get('employeeEarned') / sectionMax) * 100).setScale(1)
                );
            } else {
                sectionResult.put('managerScore', 0);
                sectionResult.put('employeeScore', 0);
            }
            sectionResult.put('strengths', agg.get('strengths'));
            sectionResult.put('weaknesses', agg.get('weaknesses'));
            sectionResult.put('gaps', agg.get('gaps'));
            sectionOutput.put(sectionName, sectionResult);
        }

        result.sectionScoresJson = JSON.serialize(sectionOutput);
        result.recommendedActionPlan = buildActionPlan(sectionOutput);
        return result;
    }

    public static String buildActionPlan(Map<String, Object> sectionOutput) {
        List<String> actions = new List<String>();
        Integer step = 1;

        for (String sectionName : sectionOutput.keySet()) {
            Map<String, Object> section = (Map<String, Object>) sectionOutput.get(sectionName);
            List<Object> weaknesses = (List<Object>) section.get('weaknesses');
            List<Object> gaps = (List<Object>) section.get('gaps');

            if (weaknesses != null) {
                for (Object w : weaknesses) {
                    actions.add(
                        step + '. Focus coaching on ' + String.valueOf(w) +
                        ' (' + sectionName + ') — schedule a ride-along or role-play on this competency.'
                    );
                    step++;
                }
            }
            if (gaps != null) {
                for (Object gapObj : gaps) {
                    Map<String, Object> gap = (Map<String, Object>) gapObj;
                    actions.add(
                        step + '. Align perception on ' + gap.get('question') +
                        ' — discuss the ' + gap.get('delta') + '-point gap between manager and rep scores.'
                    );
                    step++;
                }
            }
        }

        if (actions.isEmpty()) {
            return 'Continue reinforcing current strengths. Schedule a follow-up coaching session within 30 days to sustain performance.';
        }
        return String.join(actions, '\n');
    }

    private static Map<String, Object> initSectionAggregate() {
        return new Map<String, Object>{
            'managerEarned' => 0,
            'employeeEarned' => 0,
            'maxPoints' => 0,
            'strengths' => new List<Object>(),
            'weaknesses' => new List<Object>(),
            'gaps' => new List<Object>()
        };
    }

    private static Map<String, Object> buildResponseMap(String responsesJson) {
        Map<String, Object> mapByQuestion = new Map<String, Object>();
        if (String.isBlank(responsesJson)) {
            return mapByQuestion;
        }
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responsesJson);
        List<Object> answers = (List<Object>) root.get('answers');
        if (answers == null) {
            return mapByQuestion;
        }
        for (Object answerObj : answers) {
            Map<String, Object> answer = (Map<String, Object>) answerObj;
            String questionId = (String) answer.get('questionId');
            if (String.isNotBlank(questionId)) {
                mapByQuestion.put(questionId, answer);
            }
        }
        return mapByQuestion;
    }

    private static Decimal getQuestionMaxPoints(Map<String, Object> question) {
        List<Object> scalePoints = (List<Object>) question.get('scalePoints');
        Decimal maxWeight = 0;
        if (scalePoints != null) {
            for (Object pointObj : scalePoints) {
                Map<String, Object> point = (Map<String, Object>) pointObj;
                Object weightObj = point.get('weight');
                Decimal weight = weightObj == null ? 0 : Decimal.valueOf(String.valueOf(weightObj));
                if (weight > maxWeight) {
                    maxWeight = weight;
                }
            }
        }
        if (maxWeight == 0 && question.containsKey('points')) {
            maxWeight = Decimal.valueOf(String.valueOf(question.get('points')));
        }
        return maxWeight;
    }

    private static Decimal getScaleScore(
        Map<String, Object> question,
        Map<String, Object> response,
        String valueField
    ) {
        if (response == null || !response.containsKey(valueField) || response.get(valueField) == null) {
            return 0;
        }
        Integer selectedValue = Integer.valueOf(String.valueOf(response.get(valueField)));
        List<Object> scalePoints = (List<Object>) question.get('scalePoints');
        if (scalePoints == null) {
            return 0;
        }
        for (Object pointObj : scalePoints) {
            Map<String, Object> point = (Map<String, Object>) pointObj;
            Integer pointValue = Integer.valueOf(String.valueOf(point.get('value')));
            if (pointValue == selectedValue) {
                Object weightObj = point.get('weight');
                return weightObj == null ? 0 : Decimal.valueOf(String.valueOf(weightObj));
            }
        }
        return 0;
    }

    public static String getScaleLabel(Map<String, Object> question, Integer selectedValue) {
        if (selectedValue == null) {
            return '';
        }
        List<Object> scalePoints = (List<Object>) question.get('scalePoints');
        if (scalePoints == null) {
            return '';
        }
        for (Object pointObj : scalePoints) {
            Map<String, Object> point = (Map<String, Object>) pointObj;
            Integer pointValue = Integer.valueOf(String.valueOf(point.get('value')));
            if (pointValue == selectedValue) {
                return (String) point.get('label');
            }
        }
        return '';
    }
}