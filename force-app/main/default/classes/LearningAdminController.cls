public with sharing class LearningAdminController {
    public class MaterialSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String materialType;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Id parentMaterialId;
        @AuraEnabled public String parentTitle;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public String description;
        @AuraEnabled public String materialUrl;
        @AuraEnabled public String name;
        @AuraEnabled public Integer assignmentCount;
    }

    public class AssignmentRow {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String userEmail;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Datetime startedOn;
        @AuraEnabled public Datetime completedOn;
    }

    public class AssignResult {
        @AuraEnabled public Id courseInstanceId;
        @AuraEnabled public Integer instanceCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<MaterialSummary> getMaterialSummaries(
        String searchTerm,
        String typeFilter,
        String activeFilter
    ) {
        String soql =
            'SELECT Id, Name, Title__c, Material_Type__c, Active__c, Duration__c, Description__c, Material_URL__c, ' +
            'Parent_Material__c, Parent_Material__r.Title__c ' +
            'FROM Learning_Material__c ';
        List<String> clauses = new List<String>();
        String likeTerm;
        if (String.isNotBlank(searchTerm)) {
            likeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            clauses.add('(Title__c LIKE :likeTerm OR Name LIKE :likeTerm)');
        }
        if (String.isNotBlank(typeFilter) && typeFilter != 'All') {
            clauses.add('Material_Type__c = :typeFilter');
        }
        if (activeFilter == 'Active') {
            clauses.add('Active__c = true');
        } else if (activeFilter == 'Inactive') {
            clauses.add('Active__c = false');
        }
        if (!clauses.isEmpty()) {
            soql += 'WHERE ' + String.join(clauses, ' AND ') + ' ';
        }
        soql += 'ORDER BY Title__c NULLS LAST LIMIT 200';

        List<Learning_Material__c> materials = Database.query(soql);
        Set<Id> courseIds = new Set<Id>();
        for (Learning_Material__c m : materials) {
            if (m.Material_Type__c == 'Course') {
                courseIds.add(m.Id);
            } else if (m.Parent_Material__c != null) {
                courseIds.add(m.Parent_Material__c);
            } else {
                courseIds.add(m.Id);
            }
        }

        Map<Id, Integer> assignmentCounts = new Map<Id, Integer>();
        if (!courseIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Material__c materialId, COUNT(Id) cnt
                FROM Learning_Material_Instance__c
                WHERE Material__c IN :courseIds
                GROUP BY Material__c
            ]) {
                assignmentCounts.put((Id) ar.get('materialId'), (Integer) ar.get('cnt'));
            }
        }

        List<MaterialSummary> rows = new List<MaterialSummary>();
        for (Learning_Material__c m : materials) {
            MaterialSummary row = new MaterialSummary();
            row.id = m.Id;
            row.name = m.Name;
            row.title = m.Title__c;
            row.materialType = m.Material_Type__c;
            row.isActive = m.Active__c;
            row.duration = m.Duration__c;
            row.description = m.Description__c;
            row.materialUrl = m.Material_URL__c;
            row.parentMaterialId = m.Parent_Material__c;
            row.parentTitle = m.Parent_Material__r != null ? m.Parent_Material__r.Title__c : null;
            Id countKey = m.Material_Type__c == 'Course'
                ? m.Id
                : (m.Parent_Material__c != null ? m.Parent_Material__c : m.Id);
            row.assignmentCount = assignmentCounts.containsKey(countKey)
                ? assignmentCounts.get(countKey)
                : 0;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<AssignmentRow> getAssignments(Id materialId) {
        if (materialId == null) {
            return new List<AssignmentRow>();
        }
        Learning_Material__c root = [
            SELECT Id, Material_Type__c, Parent_Material__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];
        Id courseId = root.Material_Type__c == 'Course'
            ? root.Id
            : (root.Parent_Material__c != null ? root.Parent_Material__c : root.Id);

        List<AssignmentRow> rows = new List<AssignmentRow>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Started_On__c,
                Completed_On__c,
                Learner__c,
                Learner__r.Name,
                Learner__r.Email
            FROM Learning_Material_Instance__c
            WHERE Material__c = :courseId
            ORDER BY Learner__r.Name
            LIMIT 500
        ]) {
            AssignmentRow row = new AssignmentRow();
            row.instanceId = inst.Id;
            row.userId = inst.Learner__c;
            row.userName = inst.Learner__r != null ? inst.Learner__r.Name : null;
            row.userEmail = inst.Learner__r != null ? inst.Learner__r.Email : null;
            row.status = inst.Status__c;
            row.progress = inst.Progress__c;
            row.score = inst.Score__c;
            row.startedOn = inst.Started_On__c;
            row.completedOn = inst.Completed_On__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static Id updateMaterial(
        Id materialId,
        String title,
        String description,
        Boolean active,
        Decimal duration,
        String materialType,
        String materialUrl
    ) {
        if (materialId == null) {
            throw new AuraHandledException('Material Id is required.');
        }
        if (String.isBlank(title)) {
            throw new AuraHandledException('Title is required.');
        }
        Learning_Material__c material = [
            SELECT
                Id,
                Title__c,
                Description__c,
                Active__c,
                Duration__c,
                Material_Type__c,
                Material_URL__c,
                Passing_Score__c,
                Quiz_Time_Limit_Minutes__c,
                Quiz_Questions__c,
                Max_Attempts__c,
                Show_Results__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];
        material.Title__c = title.trim();
        material.Description__c = description;
        material.Active__c = active == true;
        material.Duration__c = duration;
        material.Material_URL__c = materialUrl;
        if (String.isNotBlank(materialType) && materialType != material.Material_Type__c) {
            material.Material_Type__c = materialType;
            if (materialType == 'Quiz' && String.isBlank(material.Quiz_Questions__c)) {
                material.Passing_Score__c = material.Passing_Score__c == null ? 70 : material.Passing_Score__c;
                material.Quiz_Time_Limit_Minutes__c = material.Quiz_Time_Limit_Minutes__c == null
                    ? 30
                    : material.Quiz_Time_Limit_Minutes__c;
                material.Show_Results__c = true;
                material.Max_Attempts__c = material.Max_Attempts__c == null ? 3 : material.Max_Attempts__c;
                material.Quiz_Questions__c = JSON.serialize(
                    new Map<String, Object>{
                        'version' => '1.1',
                        'totalQuestions' => 1,
                        'totalPoints' => 1,
                        'questions' => new List<Object>{
                            new Map<String, Object>{
                                'id' => 'q1',
                                'question' => 'Sample question - replace in Quiz Editor',
                                'type' => 'single-choice',
                                'options' => new List<String>{ 'A', 'B', 'C', 'D' },
                                'correctAnswer' => 0,
                                'points' => 1,
                                'explanation' => ''
                            }
                        }
                    }
                );
            }
        }
        update material;
        return material.Id;
    }

    @AuraEnabled
    public static Id createMaterial(
        String title,
        String materialType,
        Id parentMaterialId,
        Boolean active
    ) {
        if (String.isBlank(title)) {
            throw new AuraHandledException('Title is required.');
        }
        if (String.isBlank(materialType)) {
            throw new AuraHandledException('Material type is required.');
        }

        Learning_Material__c material = new Learning_Material__c(
            Title__c = title.trim(),
            Material_Type__c = materialType,
            Parent_Material__c = parentMaterialId,
            Active__c = active == true
        );

        if (materialType == 'Quiz') {
            material.Passing_Score__c = 70;
            material.Quiz_Time_Limit_Minutes__c = 30;
            material.Show_Results__c = true;
            material.Max_Attempts__c = 3;
            material.Quiz_Questions__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => '1.1',
                    'totalQuestions' => 1,
                    'totalPoints' => 1,
                    'questions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'q1',
                            'question' => 'Sample question � replace in Quiz Editor',
                            'type' => 'single-choice',
                            'options' => new List<String>{ 'A', 'B', 'C', 'D' },
                            'correctAnswer' => 0,
                            'points' => 1,
                            'explanation' => ''
                        }
                    }
                }
            );
        }

        insert material;
        return material.Id;
    }

    @AuraEnabled
    public static AssignResult assignToUser(Id userId, Id materialId) {
        if (userId == null || materialId == null) {
            throw new AuraHandledException('User and material are required.');
        }

        Learning_Material__c root = [
            SELECT Id, Material_Type__c, Title__c, Parent_Material__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];

        Id courseId = root.Material_Type__c == 'Course'
            ? root.Id
            : (root.Parent_Material__c != null ? root.Parent_Material__c : root.Id);

        Set<Id> materialIds = new Set<Id>{ courseId };
        for (Learning_Material__c child : [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseId AND Active__c = true
        ]) {
            materialIds.add(child.Id);
        }
        if (root.Id != courseId) {
            materialIds.add(root.Id);
        }

        Map<Id, Learning_Material_Instance__c> existingByMaterial = new Map<Id, Learning_Material_Instance__c>();
        for (Learning_Material_Instance__c inst : [
            SELECT Id, Material__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__c IN :materialIds
        ]) {
            existingByMaterial.put(inst.Material__c, inst);
        }

        List<Learning_Material_Instance__c> toInsert = new List<Learning_Material_Instance__c>();
        for (Id mid : materialIds) {
            if (!existingByMaterial.containsKey(mid)) {
                toInsert.add(
                    new Learning_Material_Instance__c(
                        Learner__c = userId,
                        Material__c = mid,
                        Status__c = 'Not Started',
                        Progress__c = 0,
                        Attempt_Number__c = 0
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Learning_Material_Instance__c inst : toInsert) {
                existingByMaterial.put(inst.Material__c, inst);
            }
        }

        AssignResult result = new AssignResult();
        result.courseInstanceId = existingByMaterial.get(courseId).Id;
        result.instanceCount = existingByMaterial.size();
        return result;
    }
}