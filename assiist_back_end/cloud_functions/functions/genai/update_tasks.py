import json
import time
import re
import os
import asyncio
import logging
from datetime import datetime, timezone
from firebase_functions import https_fn, params, options
from firebase_functions.params import StringParam, IntParam
# Import shared utilities - now using local functions
from genai.services.ai_generation_service import get_ai_generation_service

# Import firestore if not already imported
from firebase_admin import firestore, initialize_app
from typing import Dict, Any

# Configure logging
logger = logging.getLogger(__name__)

# --- DEBUG: PRINT ENV KEYS ---
print(f"--- ENV KEYS DUMP (v3) ---: {list(os.environ.keys())}")
# --- END DEBUG ---

# --- Helper Functions ---

def extract_json(content, debug=False):
    """Extract JSON from text content, handling various formatting"""
    if debug:
        print(f"DEBUG - Extracting JSON from content (length: {len(content)})")
    
    try:
        # Try to parse the entire content as JSON first
        parsed = json.loads(content)
        return {"extracted_json": content, "extra_text": None}
    except json.JSONDecodeError:
        pass
    
    # Look for JSON blocks marked with ```json
    json_match = re.search(r'```json\s*\n(.*?)\n```', content, re.DOTALL)
    if json_match:
        json_content = json_match.group(1).strip()
        try:
            json.loads(json_content)  # Validate it's valid JSON
            return {"extracted_json": json_content, "extra_text": content.replace(json_match.group(0), "").strip()}
        except json.JSONDecodeError:
            pass
    
    # Look for JSON blocks between { }
    json_match = re.search(r'(\{.*\})', content, re.DOTALL)
    if json_match:
        json_content = json_match.group(1).strip()
        try:
            json.loads(json_content)  # Validate it's valid JSON
            return {"extracted_json": json_content, "extra_text": content.replace(json_match.group(0), "").strip()}
        except json.JSONDecodeError:
            pass
    
    if debug:
        print("DEBUG - No valid JSON found in content")
    
    return {"extracted_json": None, "extra_text": content}

def insert_sms_url_in_reminder(reminder_template, message_to_encode, funnel_domain="", contact_phone=""):
    """Insert SMS URL in reminder template - using url_utils for compatibility"""
    # Call the original url_utils function for production compatibility
    from genai.shared import url_utils
    return url_utils.insert_sms_url_in_reminder(
        reminder_template=reminder_template,
        message_to_encode=message_to_encode,
        funnel_domain=funnel_domain,
        contact_phone=contact_phone
    )

def format_availability_for_ai(availability: Dict[str, Any]) -> str:
    """Format availability data for AI consumption."""
    if not availability or not availability.get("busy_periods"):
        return "No specific busy periods found in connected calendars."
    
    time_range = availability.get("time_range", {})
    busy_periods = availability.get("busy_periods", [])
    
    result = f"Availability checked from {time_range.get('start', 'N/A')} to {time_range.get('end', 'N/A')}\n"
    result += f"Total busy periods: {len(busy_periods)}\n\n"
    
    if busy_periods:
        result += "Busy periods:\n"
        for period in busy_periods:
            result += f"- {period.get('start', 'N/A')} to {period.get('end', 'N/A')}\n"
    
    return result

def generatePrompt(params):
    # Extract parameters with defaults
    user_first_name = params.get('user_first_name', '')
    business_type = params.get('business_type', '')
    business_name = params.get('business_name', '')
    business_description = params.get('business_description', '')
    addressed_as = params.get('addressed_as', '')
    first_name = params.get('first_name', '')
    last_name = params.get('last_name', '')
    email = params.get('email', '')
    recipient_phone = params.get('recipient_phone', '')
    raw_note = params.get('raw_note', '')
    relationship_details = params.get('relationship_details', {})  # Enhanced default
    personal_details = params.get('personal_details', {})  # Enhanced default
    business_details = params.get('business_details', {})  # Enhanced default
    follow_up_immediately = params.get('follow_up_immediately', True)  # Changed default from False to True
    language_examples = params.get('language_examples', "")  # Enhanced default
    notes = params.get('subset_notes', [])
    tasks = params.get('subset_tasks', [])
    appointments = params.get('subset_appointments', [])  # Now filtered by contact emails
    availability = params.get('availability', {})
    
    # --- Time-zone handling ---
    user_timezone = params.get('user_timezone', 'UTC')  # IANA ID or 'UTC'

    # Get current datetime from context (user's local time) if provided
    current_datetime = params.get('current_datetime')

    if not current_datetime:
        try:
            from zoneinfo import ZoneInfo
            user_tz = ZoneInfo(user_timezone)
        except Exception:
            user_tz = timezone.utc
            logger.warning(f"Unknown timezone {user_timezone}; falling back to UTC")

        current_datetime = datetime.now(user_tz).strftime('%A, %B %d, %Y at %I:%M %p %Z')
        logger.warning("No current_datetime provided; using generated value in user's TZ")
    
    # Prompt.
    user_message = f"""

================================
# IDENTITY & ROLE
================================

You are an elite-level executive assistant helping {user_first_name} (business type: {business_type}) nurture their relationships by managing their tasks.
These tasks are based on recent interactions and contextual information, and they need to be 'refreshed' each time {user_first_name} gives you new information (see raw_note below).

This refresh involves analyzing all existing tasks and contextual information in light of this new info and outputting an updated set of tasks where:
- Every existing task receives an operation (keep, edit, delete)
- New tasks are created based on identified follow up opportunities
- All tasks are optimized for relationship building and business objectives

For this particular instance of this process, you'll be creating tasks to help {user_first_name} nurture their relationship with {addressed_as}.
You'll be able to create tasks for {user_first_name} EXCLUSIVELY associated with {addressed_as} and draft text messages for {user_first_name} to send EXCLUSIVELY to {addressed_as}.
Any action tasks should serve the ultimate goal of text messages to {addressed_as}, since our product's primary value is in helping {user_first_name} communicate with {addressed_as}.

It's super important that each task adheres to strict guidelines and validation criteria. 

================================
# TASK STATE REFRESH PROCESS  
================================

You are performing a comprehensive STATE REFRESH of all tasks based on new information:

1. Current State Analysis: Analyze how the new note affects ALL existing tasks
2. Context Mapping: Build analysis tables to understand relationships and topics  
3. Task Set Creation: Analyze existing tasks and potential new tasks together to determine the optimal task set:
   - For each existing task: keep (unchanged), edit (modify), or delete (no longer needed)
   - For potential new tasks: create (worthwhile) or discard (not valuable enough)
4. Validation: Set Validation -> Task Validation -> Claim Validation

CRITICAL: This product is designed to help {user_first_name} with their follow up with {addressed_as}, where follow up is defined as:
future communication after an appropriate interval of time for the purposes of furthering the relationship or business objectives.

================================
# INPUT DATA (<facts>)
================================

The information below is to be considered the only source of truth.

## NEW INFORMATION
###Raw Note: {raw_note}
Contact "Addressed As" Name: {addressed_as}
Contact First Name: {first_name}
Contact Last Name: {last_name}
Today's Datetime: {current_datetime}
User's Time Zone: {user_timezone}
Immediate Follow-up Required: {follow_up_immediately}

## CURRENT TASK STATE
Existing Tasks: {tasks}

## CONTEXTUAL INFORMATION
<contextual_information>
Relationship Details: {relationship_details}
Personal Details: {json.dumps(personal_details, indent=2)}
Business Details: {json.dumps(business_details, indent=2)}
Previous Notes: {notes}
Appointments: {appointments}
Availability: {json.dumps(availability, indent=2)}
</contextual_information>

## USER CONTEXT
User's Name: {user_first_name}
User Communication Style Examples: 
{language_examples or "Professional but warm communication style"}
Business Type: {business_type}
Business Name: {business_name}
Business Description: {business_description}

--------------------------------
## Interpreting Contextual Information
--------------------------------

### Appointments & Availability
--------------------------------
- The appointments provided in the contextual information are already filtered and are all with {addressed_as}. These are scheduled commitments to consider during all aspects of task creation.
- If you don't see an appointment in contextual information, assume it has not been scheduled yet.
- Availability data provides {user_first_name}'s free/busy status from connected calendars and should be used to avoid scheduling conflicts.


================================
# CONTEXT ANALYSIS TABLES 
================================

- Consider all information in <facts> as you create the following tables.

--------------------------------
## RELATIONSHIP TABLE
--------------------------------

Create a table that captures key relationship parameters:

| aspect                           | details                      | evidence                     |
|----------------------------------|------------------------------|------------------------------|
| Relationship Duration            | Duration                     | Evidence                     |
| Interaction Frequency            | Frequency                    | Evidence                     |
| Familiarity Level                | High/Medium/Low              | Based on analysis            |
| Appropriate Communication Style  | Style                        | Based on relationship        |


--------------------------------
## TOPICS TABLE
--------------------------------

Create a table identifying relevant topics from the interaction and context while following the rules below:

### KEY TOPICS
--------------------------------
These topics are critical to the relationship and MUST be included in the topics table.
- Acknowledgment of communication from {addressed_as}.
- Appointments that need to be scheduled
- Referral opportunities
- Any deliverables mentioned in facts that {user_first_name} owes to {addressed_as}
- Explicit task requests from {user_first_name} in raw_note
- Commitments by {user_first_name} to {addressed_as} and visa-versa

### COMMON MISTAKES
--------------------------------
- Creating topics for work for the user that is not explicitly called for in the raw note or by pre-requisite transformation.
- Creating topics to get information that the user probably already has based on inference from the raw note.
- Misidentification of dependencies.
  * Example: if a contact owes a deliverable, {user_first_name}'s follow up is not dependent on the contact failing to deliver.

### RELATIONSHIP IMPORTANCE
--------------------------------
1 = Tangential mention with minimal connection to relationship
2 = Contextual information that provides background but doesn't directly advance relationship
3 = Moderate importance that could strengthen relationship if addressed
4 = Significant opportunity to advance relationship or business goals
5 = Critical information that must be addressed to maintain or progress relationship

### TOPIC STATUS
--------------------------------
- Open: Further conversation or action would be reasonable to have
- Closed: No further conversation or action is warranted outside of acknowledging the topic.

### RELEVANCE WINDOW
--------------------------------
- Specify date range for which it is appropriate to communicate about and/or take action on the topic (e.g., "now - 2 weeks" or "30 days - 90 days")
- Use "Ongoing" for topics with long-term relevance
- Use "None" for topics that are closed

### TASKS WARRANTED
--------------------------------
When determining which tasks are warranted, follow these rules:
- Assume interactions in the raw note just happened unless otherwise specified in the note. 
- An immediate message task is ALWAYS warranted after an interaction with {addressed_as} unless otherwise specified in the note.
- A future message task is ALWAYS warranted for follow up on anything the user needs from the contact (documents, information, decisions, approvals).

**TASKS WARRANTED**
For each task type, determine if it would further the relationship or business objectives. You MUST mark 'Yes' if so.
- `immediate_message_task_warranted`: "Yes" or "No" - Communication to contact that should happen now
- `future_message_task_warranted`: "Yes" or "No" - Communication to contact that should be scheduled for future execution
- `immediate_action_task_warranted`: "Yes" or "No" - Internal work that should happen now

**TASKS WARRANTED JUSTIFICATION**
- For each warranted task type, provide specific justification
- You MUST NOT use conditional language like "will not be warranted until..." or "will be warranted if..."

**TASK DEPENDENCIES**
List of dependency relationships between warranted tasks:
- Format: `["task_type_A depends on task_type_B's completion"]`

--------------------------------
## TOPICS TABLE
--------------------------------

| topic_description            | topic_source                 | relationship_importance      | topic_status                 | topic_status_justification   | relevance_window             | immediate_message_task_warranted | immediate_message_task_justification | future_message_task_warranted | future_message_task_justification | immediate_action_task_warranted | immediate_action_task_justification | task_dependencies |
|------------------------------|------------------------------|------------------------------|------------------------------|------------------------------|------------------------------|----------------------------------|-------------------------------------|------------------------------|-----------------------------------|------------------------------|-------------------------------------|------------------|
| relevant topic               | Note/Details Fields/etc.     | 1-5                          | Open/Closed                  | why this status              | date-range/ongoing/none      | Yes/No                           | justification if warranted           | Yes/No                       | justification if warranted         | Yes/No                       | justification if warranted           | ["dependency relationships"] |
| ...                          | ...                          | ...                          | ...                          | ...                          | ...                          | ...                              | ...                                 | ...                          | ...                               | ...                          | ...                                 | ...              |




================================
# INITIAL TASK CREATION
================================

Create an initial set of tasks based on the topics table that we will validate and revise in the next steps.

--------------------------------
### FIELD DEFINITIONS
--------------------------------

#### Core Task Fields:
--------------------------------
- id: Exact task ID from input data if this row relates to an existing task (null for "create" operations)
- title: Brief description of the task
- body: For message tasks: text of the message to send to {addressed_as}. For action tasks: description of the action to take
- notification: Reminder text from you to {user_first_name} explaining what this task is about
- actionable_date: The earliest date it makes sense to complete the task (YYYY-MM-DDTHH:mm:ss±HH:MM)
- due_date: The latest date it makes sense to complete the task (YYYY-MM-DDTHH:mm:ss±HH:MM)
- type: Task type (message or action)
  * Message Task: "A message the user should send to the contact
  * Action Task: "An action the USER must take (NOT the system/assistant)
- operation: What to do with this task
  * keep: Keep the existing task as-is (no changes needed)
  * edit: Update the existing task (content or timing changes)
  * delete: Remove the existing task (no longer needed or applicable)
  * create: Create a new task based on the note/context
  * discard: Potential task considered but not worth creating

#### Task Metadata Fields:
--------------------------------
- date_calculation: Show your date math (e.g., "June 19 + 14 days = July 3" or "Today = June 19, immediate follow-up")
- score: Value score 1-5 based on relationship/business impact
  * 1 = Minimal value: Nice-to-have but not impactful
  * 2 = Low value: Maintains relationship status quo with minor positive effect
  * 3 = Moderate value: Clear positive impact on relationship or meaningful progress
  * 4 = High value: Significant advancement of relationship or substantial progress toward key goals
  * 5 = Critical value: Direct path to achieving primary business/relationship objectives
- score_evidence: Supporting evidence from facts
- pre_requisites: Array of dependencies that need transformation (analysis only)
- prerequisite_transformations: Record of transformation when pre-requisites were converted to independent tasks
  * Object with "Before" (original task body) and "After" (transformed task body) if transformation occurred
  * null if no transformation was needed

================================
## STEP 1: CREATE INITIAL TASKS
================================

Create a table with an initial set of tasks that includes all existing tasks and any new tasks warranted based on the topics table, new information, and context. 

--------------------------------
### TASK CREATION PROCESS
--------------------------------

- Tasks are ONLY for {user_first_name} about {addressed_as}.
- YOU create tasks.  {user_first_name} PERFORMS tasks.

--------------------------------
### TASK CREATION RULES
--------------------------------

#### Tasks Must Be Independent (Pre-requisite Transformation)
--------------------------------
Core Principle: Every task must be actionable at the actionable_date without depending on other actions by {user_first_name} being completed first.

Process:
- List Prerequisites: Can this task be completed right now with available information?  If not, list all pre-requisites.
- If Prerequisites Exist: Transform using the "Do X so that Y" pattern in the action task body in order to create an independent action task
- If a task has been transformed into a pre-requisite, it must be removed from the task table and replaced with the pre-requisite task.

Example:
- Original action task body: "Send market analysis to Sarah" 
- Dependencies: Market analysis must be created first
- Transformed action task body: "Prepare current market analysis for Sarah's area so that you can send it to her"

Prerequisites Array Format: Use array of strings (e.g., ["Create proposal", "Research pricing"]) - this is for analysis only, final tasks must be independent.

#### Tasks Must Have Complete Coverage
--------------------------------
- Every topic that warrants a task must be represented in a task, but a 1-to-1 mapping is not required.
- Every task type warranted in the topics table MUST have a corresponding task in the task table NOW (do not defer task creation).
- Completion-Creation: If notes mention completing an action task, you must create a new task for the intended outcome.
  * e.g. Note: "I just completed: Prepared list for Mike so that I can send it to him" ->  New Task: "Send the prepared list to Mike" 
- Deliverables: If the topic relates to {user_first_name} owing a deliverable to {addressed_as}, create an action task to prepare the deliverable in the X so that Y format as in "prepare the deliverable so that it can be delivered."

Mistakes:
- Not creating tasks for warranted topics.

#### Task Must Have Correct Type
--------------------------------
- 'Message' tasks require drafting a text message for {user_first_name} to send to {addressed_as}
- 'Action' tasks require {user_first_name} to perform an internal action that cannot be achieved via text messaging (e.g., research, document preparation, making phone calls)
  * Use 'action' when the task is a pre-requisite transformation case.
  * Do not use 'action' simply because guidance mentions 'scheduling' or 'reminders' if the core purpose is future communication.  If an appointment isnt' scheduled, it should be initiated as a message task.
- You MUST use 'message' unless one of these applies: 
  * Action is explicitly required in raw note.
  * The task is a pre-requisite transformation case.
  * The task is impossible with a message.

#### Task Must Have Correct Timing
--------------------------------
- You must not set due dates on holidays or when the user is not available.
- For topics that warrant immediate follow-up, actionable_date must be set to {current_datetime}.
- For action tasks there must be sufficien time between actionable_date and due_date delta for the action to be completed by the user.

#### Tasks Must Not Have Contradictions
--------------------------------
- You must not allow tasks to have internal contradictions.
- You must not allow contradictions between tasks.

#### Appointment Reminder Rules
--------------------------------
CRITICAL: Each appointment requires its own set of tasks. Do NOT delete existing appointment tasks when processing new appointments unless the appointment is cancelled.

For each appointment mentioned in the raw note or contextual information:
- Create a MESSAGE task to remind {addressed_as} 24 hours before the appointment
  * actionable_date: 24 hours before appointment start time
  * due_date: End of business day the day before appointment
  * body: Friendly reminder message about the upcoming appointment
- Create an ACTION task to prompt {user_first_name} to log post-appointment notes
  * actionable_date: 15 minutes after appointment start time
  * due_date: End of business day of appointment
  * body: Link to log notes with correct appointment_id
- All natural language references to times in tasks/messages must be in user's timezone. 
  * Appointments/availability data is in UTC - convert first.
  * Example: UTC "2024-01-15T18:00:00Z" → EST "2024-01-15T13:00:00-05:00" (1:00 PM)  
- For multiple reminder message tasks, use variety in greeting and sign-off language.
  * Examples: 
    ** "Hey Ben! Just a reminder that we have our appointment tomorrow at 1:00 PM MST.  Looking forward to it!"
    ** "Hi Ben! Just a quick reminder that we have our appointment tomorrow at 1 PM MST.  Talk soon!"

#### Scheduling Rules
--------------------------------
For message tasks involving scheduling: 
- You must not propose appointments (meetings, calls, etc.) on holidays or during a user's busy periods.
- Proactively propose 2 specific appointment times (e.g. Monday at 2pm or Tuesday at 4pm) if one has not been proposed already.
- Do not propose appointments for less than 24 hours in advance.

#### Message Quality Rules
--------------------------------
- Write message drafts in {user_first_name}'s authentic voice by learning the tone, structure, and stylistic patterns from the text message examples.
- Avoid declarative statements about the contact's thoughts and feelings in message drafts (soften the language with qualifiers like "it seems like").
- Treat personal topics like death and divorce with nuance and restraint in message drafts.
- Each message draft contains at most ONE question unless otherwise requested by the user.
- You must combine all same-day message tasks unless it would produce an awkward message.
- Ensure message content reflects all available context: greetings, tone, timing references, and conversation flow should be consistent with recent interactions, relationship history, business context, and personal circumstances mentioned in the facts.
- When the raw note contains attachment URLs in the "Attached Files:" section, you MUST include those attachment links at the end of the message body with a line break above each link and other text.
  * If there is an understandable title you may use Title: URL format.
  * Else only use the URL with appropriate whitespace/linebreaks.

#### Notification Rules
--------------------------------
Create a notification that captures the essence of the task.
- Use a conversational tone like a helpful human assistant
- Include a friendly greeting to {user_first_name} in reminders
- Don't assume the user is aware of tasks you're assigning them ahead of time.
- Make language in reminders appropriate to the timing (immediate vs. scheduled)
- Avoid unecessarly exposition.

#### Operation Rules
--------------------------------
- Edit and delete based on evidence - do not remove information from a task simply because you are unsure if the information is still relevant.
- Common mistakes
  * Deleting tasks because they are overdue.
  * Deleting reminder tasks for one appointment with the incorrect justification that they are redundant to another appointment.

--------------------------------
### TASK TABLE
--------------------------------

#### Field Definitions
--------------------------------
- prerequisite_transformation: {{"Before": "original task body", "After": "transformed task body"}} or null


| id                 | title                 | body                      | notification              | actionable_date           | due_date                  | date_justification        | date_calculation          | type                      | type_justification        | operation                 | operation_justification   | score       | score_justification       | score_evidence            | pre_requisites            | prerequisite_transformation   |
|--------------------|-----------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|---------------------------|-------------|---------------------------|---------------------------|---------------------------|-------------------------------|
| task_id or null    | brief description     | message text or action    | reminder text for user    | YYYY-MM-DDTHH:mm:ss       | YYYY-MM-DDTHH:mm:ss       | why these dates           | explicit date math        | message/action            | why this type             | keep/edit/delete/create   | why this operation        | 1-5         | why this score            | evidence array            | pre_requisites array      | transformation record or null |
| ...                | ...                   | ...                       | ...                       | ...                       | ...                       | ...                       | ...                       | ...                       | ...                       | ...                       | ...         | ...                       | ...                       | ...                       | ...                       | ...                           |



================================
## STEP 2: TOPICS TO TASKS VALIDATION & REFINEMENT
================================

--------------------------------
### Topics to Tasks Validation 
--------------------------------

- Validate that every topic in the topics table is correctly represented in the tasks table.
- Do not judge whether or not a task is warranted based on context - this has already been done in the previous step.
- This is a mechanical validation and you must strictly follow the algorithm below.

### COVERAGE
--------------------------------

**STEPS:**
1. Create tasks_warranted_actual object for all three task types (immediate_message_task, future_message_task, immediate_action_task)
  * You MUST NOT exclude any task types from the tasks_warranted_actual object.
2. Compare: warranted="Yes" from topics_table vs actual task from task_table
3. **RULE:** If warranted="Yes" AND actual=null → FAIL and fix
4. Create missing tasks and update validation

**NO EXCEPTIONS:** "Warranted" designation in topics table means task must exist NOW (even if scheduled for future)

### TIMING
--------------------------------
- Check that task timing matches warrant requirements (immediate vs future)
  * For immediate task types, if the actionable_date does not equal current_datetime (INCLUDING TIME) -> FAIL & FIX TIMING

### TYPE
--------------------------------
- Ensure task types are appropriate for the topic and dependency type. If not, FAIL & FIX TYPE

--------------------------------
### Topics to Tasks Validation Table
--------------------------------

Create the table below with one row per topic in the topics table:

#### topic_description
--------------------------------
- Copy exact text from topics table topic_description column.

#### tasks_warranted_actual
--------------------------------
- Object showing warranted status from topics table paired with actual task from task table
  * Format: `{{"task_type": {{"warranted": "Yes/No"}}, "actual": "title"}}`
  * MUST include ALL task types (immediate_message_task, future_message_task, immediate_action_task) regardless of warranted status

#### validation_subchecks
--------------------------------
- List each sub-check and its PASS/FAIL status
  * Format: "Coverage: PASS/FAIL, Timing: PASS/FAIL, Type: PASS/FAIL"

#### status
--------------------------------
- PASS: All tasks from warranted tasks column exist with valid task objects (no null values) else FAIL

#### fix_applied
--------------------------------
- MUST contain a fix.
- Fix MUST BE applied to the task table.
- You MUST NOT state a fix was applied if the tasks table was not updated.
- Common mistakes:
  * Using conditional language like "fix will be applied if needed"
  * Stating a fix was applied when the task table is unchanged.


| topic_description        | tasks_warranted_actual   | validation_subchecks     | status                   | status_reason            | issues_identified        | fix_needed               | fix_applied              | fix_reasoning            | original_state           | final_state              |
|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|
| specific topic text      | warranted vs actual      | sub-check: PASS/FAIL     | PASS/FAIL                | why this status          | missing/incorrect tasks  | change required          | exact change made        | why this fix or NA       | tasks before changes     | tasks after fix          |
| ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      |


================================
## STEP 3: TASK-LEVEL VALIDATION & REFINEMENT
================================

-Audit the set-level validation table with a critical eye and look for opportunities to fail it. 
-Perform validation of each individual task for internal consistency and readiness after set-level issues are resolved.
-Do this by building a task-level validation table with one row per validation check.

--------------------------------
### Task-Level Validation Checks
--------------------------------

You must follow this process during validation:
- Perform each check labeled with ### in the order listed below.
- Pass or fail each sub-check based on the criteria defined.
- If any sub-check fails, the entire check fails.

#### Pre-Requisite Transformation
--------------------------------
- Are all pre-requisites been identified? If no → FAIL
- Have all pre-requisites been transformed correctly per pre-requisite transformation rules? If no → FAIL

#### Task Timing  
--------------------------------
- Are all timing issues represented in the task table? If no → FAIL
- Are there time-related logical conflicts? If yes → FAIL
- Are all immediate follow-up tasks scheduled for the current datetime? If no → FAIL
- Are there any unresolved task issues per our task timing rules? If yes → FAIL

#### Scheduling Rules
--------------------------------
- For message tasks involving scheduling: Are all scheduling rules followed according to the Scheduling Rules section? If no → FAIL

#### Message Quality
--------------------------------
- Are there any grammatical errors? If yes → FAIL
- Is there any awkward phrasing? If yes → FAIL
- Does message sound like {user_first_name} based on the style examples? If no → FAIL

#### Intra-Task Contradictions
--------------------------------
- Does the task contain any internal contradictions within its content, timing, or intent? If yes → FAIL


--------------------------------
### Task Validation Table
--------------------------------

-Create the table below with one row per validation check above
- Apply fixes to individual tasks in the task table.

- validation_subchecks: List each sub-check for the validation check and its PASS/FAIL status
  * Format: "Sub-check Name: PASS/FAIL, Another Sub-check: PASS/FAIL"

  
| validation_check         | validation_subchecks     | status                   | status_reason            |
|--------------------------|--------------------------|--------------------------|--------------------------|
| check name               | sub-check: PASS/FAIL     | PASS/FAIL                | why this status          |
| ...                      | ...                      | ...                      | ...                      |


================================
## STEP 4: CLAIM-LEVEL VALIDATION & REFINEMENT
================================

- Audit task claims and the claim verification process with a critical eye and look for opportunities to fail them. 
- AFTER task-level validation is complete, perform claim-level verification for all tasks passing Step 3.
- Do this by building two validation tables: first verify the factual accuracy of claims, then validate that the claim verification process was followed correctly.

--------------------------------
### CLAIM VALIDATION PROCESS
--------------------------------

#### Sentence Decomposition
--------------------------------
MANDATORY SYSTEMATIC PROCESS:
1. Split the message text at every sentence boundary (. ! ? and emoji sequences)
2. Create a numbered list of ALL sentences in order (including greetings, expressions, everything)
3. Every sentence from this list MUST appear in the validation table below - no exceptions
4. Number each sentence for tracking: [1] sentence text, [2] sentence text, etc.

#### Claim Identification
--------------------------------
For each sentence in your numbered list, extract ALL factual claims. This includes implicit claims.
- Include assertions about external facts, events, or owner's stated actions/availability/commitments (e.g., "I will send the report", "I can meet Tuesday")
- Treat significant owner opinions, judgments, or recommendations as claims requiring verification
- Identify all specific details within sentences (assertions, implications, etc.) as separate claims
- If a sentence contains no factual claims (like greetings), list it anyway with evidence: [{{"claim": "No factual claims", "evidence": "Pure greeting/expression"}}]

Claim Extraction Examples:
- Sentence: 'Does Tuesday or Wednesday work for our call?'; Claim: 'The user is available on Tuesday or Wednesday'

#### Find Evidence for Claims
--------------------------------
Next, pair each claim with the MOST CONCISE direct quote from <facts> that directly confirms the assertion.
- Evidence must explicitly pertain to the claim's subject. 
- Availability claims can be substantiated by the availability data in the facts table.
- When finding evidence, avoid inference based on context or other subjects
- Evidence must substantiate the specific event or state described, including all details mentioned in the claim

#### Verify Claims
--------------------------------
Next, verify each claim by checking if the evidence directly confirms the assertion.
- If evidence is insufficient, mark the claim as unverified
- If evidence is sufficient, mark the claim as verified

PASS/FAIL Examples:
- Evidence (sentence from raw note): 'We have agreed to train their team on AI.'
  * PASS - Sentence: "What days would work for the training?"; Claim: "We've agreed to schedule training"; Status Reason: "The user has agreed to schedule training"
  * FAIL: Sentence: "Now that our training is scheduled" Claim: "The training is scheduled"; Status Reason: "The evidence does not support the claim."
- Availability Evidence: "Busy periods: June 27 10-11am only"
  * PASS - Sentence: "I'm available Monday 2pm, Tuesday 3pm."; Claim: "Available at these times"; Status Reason: "No conflicts with documented busy periods"
  * FAIL - Sentence: "I'm available June 27 10:30am."; Claim: "Available at this time"; Status Reason: "Conflicts with documented busy period"
- Implicit Claim Evidence: "Eric called with news about the timeline"
  * FAIL - Phrase: "I just got your call"; Claim: "Eric did not speak with user during call"; Status Reason: "there is no evidence that the user missed Eric's call.  the user might have spoken with Eric when he called."
  * PASS - Phrase: "Thanks for calling about the timeline change"; Claim: "Eric called about timeline"; Status Reason: "Evidence confirms Eric called with updates about timeline"
- Contextual Evidence Failure: 
  * FAIL - Sentence: 'Great meeting with you today, Mike'; Claim: 'I met with Mike today.'; Status Reason: "The actionable date for the message is 3 days after the note for the meeting was logged."

#### Resolution
--------------------------------
- If a claim is unverified, set resolution to "Remove" or "Modify" and provide a justification
- If a claim is verified, keep it in the message

#### Modification Rules
--------------------------------
- Modify UNVERIFIED sentences to remove all unsupported claims
- Modifications MUST ONLY use information directly verifiable from facts
- Rephrase using general language consistent with original meaning if facts are not available

#### Final Message Construction:
--------------------------------
Assemble the final message by revising task body as follows.
- For sentences marked 'Keep' or where final_state is 'NA', use the original sentence text
- For sentences marked 'Modify', you MUST use the exact text provided in the final_state column.
- For sentences marked 'Remove', you MUST omit them entirely
- Ensure the revised message flows naturally

--------------------------------
### Claim Validation Table
--------------------------------

- Create the table below with one row per sentence. 

- original_state: Exact sentence text before any changes or NA if no changes are needed
  * "I'll send you the report tomorrow"
  * "I know you're interested in the pricing details" 
  * "We discussed this at the conference last week"

  - fix_applied: Specific text change made to remove unverified claims or NA if no changes are needed
  * "Replaced 'tomorrow' with 'soon' to remove unverified timing commitment"
  * "Removed 'I know you're interested' assumption and kept factual content only"
  * "Deleted entire sentence - no evidence found for conference discussion"

- final_state: Resulting sentence text after verification fix or NA if no changes are needed
  * "I'll send you the report soon"
  * "Here are the pricing details"
  * "REMOVED"

- evidence contains claim/evidence pairs: [{{"claim": "I'll send tomorrow", "evidence": ""}}, {{"claim": "report exists", "evidence": "mentioned in business_details"}}]


| sentence                 | evidence                 | status                   | status_reason            | issues_identified        | fix_needed               | fix_applied              | fix_reasoning            | original_state           | final_state              |
|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|
| specific sentence text   | claim/evidence pairs     | PASS/FAIL                | why this status          | unverified claims        | change required          | exact change made        | why this fix or NA       | exact sentence before    | sentence after fix       |
| ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      |


--------------------------------
### Claim Meta-Validation Checks
--------------------------------

CRITICAL RULE: If any sub-check fails, the entire check fails.

#### Sentence Decomposition
--------------------------------
CRITICAL VALIDATION STEP:
1. Break the message into numbered sentences: [1] sentence, [2] sentence, etc.
2. Count total sentences in message
3. Verify claim validation table has EXACTLY the same number of rows as sentences
4. For each numbered sentence, confirm it appears in the validation table
5. If sentence count doesn't match or any sentence is missing → FAIL and add the missing sentences

#### Claim Identification  
--------------------------------
- Does the claim validation table include all assertions about external facts, events, or user's stated actions/availability/commitments as claims? → If no, FAIL
- Does the claim validation table treat significant user opinions, judgments, or recommendations as claims requiring verification? → If no, FAIL

Claim Identification Error Example:
- Sentence: 'Does Tuesday or Wednesday work for our call?'; Missed Claim: 'The user is available on Tuesday or Wednesday'

#### Evidence Standards
--------------------------------
- Did you find a direct quote from facts for each claim? → If no, FAIL
- Does evidence explicitly pertain to the claim's subject without requiring inference? → If no, FAIL
- Is evidence sufficient to substantiate the specific event/state described including all details mentioned in claim? → If no, FAIL

--------------------------------
### Claim Meta-Validation Table
--------------------------------

-Create the table below with one row per process validation check above (all checks must be included):
  * Sentence Decomposition
  * Claim Identification  
  * Evidence Standards

| validation_check         | status                   | status_reason            | issues_identified        | fix_needed               | fix_applied              | fix_reasoning            | original_state           | final_state              |
|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|--------------------------|
| check name               | PASS/FAIL                | why this status          | specific problems found  | change required          | exact change made        | why this fix or NA       | state before changes     | state after fix          |
| ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      | ...                      |


================================
## OUTPUT 
================================

--------------------------------
### JSON FORMATTING RULES
--------------------------------

1. Always use proper JSON syntax with no errors or malformed properties
2. Never use empty or incomplete property values like "analysis_tables": ,
3. For empty objects, use {{}} - Example: "analysis_tables": {{}}
4. For empty arrays, use [] - Example: "relationship_table": []
5. Never include trailing commas in arrays or objects
6. All properties must have valid values (object, array, string, number, boolean, or null)
7. Use null instead of empty values - Example: "details": null
8. Validate your JSON structure before finishing to ensure it's parseable

--------------------------------
### OUTPUT FORMAT
--------------------------------

TASK OUTPUT FORMAT DEFINITIONS:

For operation: "keep" and "delete":
- Full task object but no validation arrays or tables.

For operation: "edit" and "create":
- Full task object
- Validation Arrays: `task_validation` and `claim_validation"

```json
{{
  "tasks": [
    {{
      "id": "task-uuid or null",
      "type": "message|action",
      "title": "Task title", 
      "body": "Task content",
      "assistant_message": "Natural reminder text",
      "actionable_date": "YYYY-MM-DDTHH:mm:ss±HH:MM",
      "due_date": "YYYY-MM-DDTHH:mm:ss±HH:MM",
      "operation": "create|edit|delete|keep",
      
      "task_metadata": {{
        "task_creation": {{
          "score": "1-10",
          "score_evidence": "Evidence supporting score",
          "score_justification": "Why this score",
          "type_justification": "Why message/action type",
          "operation_justification": "Why create/edit/delete/keep",
          "date_justification": "Why these dates are appropriate",
          "date_calculation": "Show your date math",
          "pre_requisites": "Dependencies or prerequisites",
          "prerequisite_transformation": "Record of transformation when pre-requisites were converted to independent tasks"
        }},
        "task_validation": [
          {{
            "validation_check": "Pre-Requisite Transformation|Task Timing|Scheduling Rules|Message Quality|Intra-Task Contradictions",
            "validation_subchecks": "Sub-check Name: PASS/FAIL, Another Sub-check: PASS/FAIL",
            "status": "PASS|FAIL",
            "status_reason": "Why this status"
          }}
        ],
        "claim_validation": [
          {{
            "sentence": "Specific sentence text",
            "evidence": [{{"claim": "specific claim text", "evidence": "quoted text from facts"}}],
            "status": "PASS|FAIL",
            "status_reason": "Why this status",
            "issues_identified": "Unverified claims or NA",
            "fix_needed": "Change required or NA",
            "fix_applied": "Exact text change made or NA",
            "fix_reasoning": "Why this fix or NA if no issues were found",
            "original_state": "Sentence before changes or NA",
            "final_state": "Sentence after fix or NA"
          }}
        ],
        "claim_meta_validation": [
          {{
            "validation_check": "Sentence Decomposition|Claim Identification|Evidence Standards",
            "status": "PASS|FAIL",
            "status_reason": "Why this status",
            "issues_identified": "Process problems found or NA",
            "fix_needed": "Process correction required or NA",
            "fix_applied": "Process correction made or NA",
            "fix_reasoning": "Why this process fix or NA if no issues were found",
            "original_state": "What was processed during verification or NA",
            "final_state": "Verification state after corrections or NA"
          }}
        ]
      }}
    }}
  ],
  "analysis_tables": {{
    "relationship_table": [
      {{
        "aspect": "Relationship aspect",
        "details": "Detail description",
        "evidence": "Supporting evidence"
      }}
    ],
    "topics_table": [
      {{
        "topic_description": "Relevant topic",
        "topic_source": "Source document/section",
        "relationship_importance": 1-5,
        "topic_status": "Open/Closed",
        "topic_status_justification": "Explanation for why this topic is open or closed",
        "relevance_window": "start_date - end_date or Closed/Ongoing",
        "immediate_message_task_warranted": "Yes/No",
        "immediate_message_task_justification": "Justification if warranted",
        "future_message_task_warranted": "Yes/No",
        "future_message_task_justification": "Justification if warranted",
        "immediate_action_task_warranted": "Yes/No",
        "immediate_action_task_justification": "Justification if warranted",
        "task_dependencies": ["future_action_task depends on immediate_message_task's completion"]
      }}
    ],
    "topics_to_tasks_validation": [
      {{
        "topic_description": "Relevant topic", 
        "tasks_warranted_actual": "Object with warranted task types as keys, actual task objects as values (or null if missing)",
        "validation_subchecks": "Coverage: PASS/FAIL, Timing: PASS/FAIL, Type: PASS/FAIL",
        "status": "PASS|FAIL",
        "status_reason": "Why this status", 
        "issues_identified": "Specific problems found or NA",
        "fix_needed": "Change required or NA",
        "fix_applied": "Exact change made or NA",
        "fix_reasoning": "Why this fix or NA",
        "original_state": "State before changes or NA", 
        "final_state": "State after fix or NA"
      }}
    ]
  }}
}}
```

CRITICAL OUTPUT RULES:
- Follow all JSON formatting rules above.
- Output ONLY the JSON structure above
- Do NOT generate markdown tables or analysis text outside the JSON 
- All analysis must be included inside the "analysis_tables" JSON object
- Do NOT include any explanatory text before or after the JSON
"""

    return {
        'userMessage': user_message,
        'systemMessage': 'You are an elite executive assistant specializing in relationship management and task optimization.'
    }


def needs_claim_validation_fixes(parsed_response):
    """Check if response contains tasks that need claim validation fixes by programmatically comparing task bodies to claim validation results."""
    if not isinstance(parsed_response.get('tasks'), list):
        return False
    
    for task in parsed_response['tasks']:
        if task.get('type') != 'message':
            continue  # Only check message tasks
            
        task_body = task.get('body', '')
        task_metadata = task.get('task_metadata', {})
        claim_validation = task_metadata.get('claim_validation', [])
        
        # Check if any failed claim validations weren't properly applied to task body
        for claim_entry in claim_validation:
            if claim_entry.get('status') == 'FAIL':
                original_phrase = claim_entry.get('original_state', '')
                corrected_phrase = claim_entry.get('final_state', '')
                
                # If the task body still contains the problematic original phrase
                # and doesn't contain the corrected phrase, it needs fixing
                if (original_phrase and 
                    original_phrase in task_body and 
                    corrected_phrase and 
                    corrected_phrase not in task_body):
                    return True
    
    return False


def apply_claim_validation_fixes(original_response, ai_service, debug_mode=False):
    """Apply claim validation fixes using the fixer model."""
    
    if debug_mode:
        print("Applying claim validation fixes...")
    
    try:
        # Extract only the tasks that need fixing and their relevant validation data
        tasks_needing_fixes = []
        for i, task in enumerate(original_response.get('tasks', [])):
            task_metadata = task.get('task_metadata', {})
            meta_validation = task_metadata.get('claim_meta_validation', [])
            
            # Check if this task has failed claim validation (we'll rely on the programmatic check now)
            has_failed_claims = any(claim.get('status') == 'FAIL' for claim in task_metadata.get('claim_validation', []))
            
            if has_failed_claims:
                # Include only the essential data for fixing
                task_data = {
                    "task_index": i,
                    "original_body": task.get('body', ''),
                    "claim_validation": task_metadata.get('claim_validation', []),
                    "claim_meta_validation": meta_validation
                }
                tasks_needing_fixes.append(task_data)
        
        if not tasks_needing_fixes:
            if debug_mode:
                print("No tasks actually need claim validation fixes")
            return original_response
            
        # Fixer prompt with only relevant data
        fixer_prompt = f"""## TASK: Fix Claim Validation Issues

You are being called to fix tasks where claim validation identified unverified claims but the fixes were not applied to the task body.

## TASKS NEEDING FIXES
{json.dumps(tasks_needing_fixes, indent=2)}

## YOUR JOB

1. **For each message task with claim validation issues**:
   - Start with the complete original message body
   - For each phrase with status "FAIL" in the claim_validation table:
     * Identify the problematic phrase in context
     * Replace it with the validated text from "final_state" 
     * **CRITICAL**: Adjust surrounding text as needed to ensure natural flow and grammar
     * If direct replacement creates awkward transitions, rewrite the surrounding sentence(s) to incorporate the validated content smoothly

2. **Update the task body field** with the corrected message

3. **Verify** the final message flows naturally, maintains proper grammar, and contains no unverified claims

KEY PRINCIPLE: Always prioritize natural flow and readability while incorporating all validated content.

EXAMPLE - Context Adjustment:
- Original: "Since I have availability next week, would Tuesday work for our call?"  
- Validated phrase: "I'd love to schedule a call soon"
- ❌ Awkward: "Since I'd love to schedule a call soon, would Tuesday work for our call?"
- ✅ Natural: "I'd love to schedule a call soon - would next week work for you?"

## OUTPUT FORMAT
```json
{{
  "fixes": [
    {{
      "task_index": 0,
      "original_body": "Original complete task body text",
      "fixed_body": "Complete task body with all claim fixes applied"
    }}
  ]
}}
```"""
        
        # Call AI service for fixes
        anthropic_messages = [{"role": "user", "content": fixer_prompt}]
        gemini_prompt_text = fixer_prompt
        
        raw_content, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.1,
            max_tokens=4096
        ))
        
        if error_message:
            print(f"❌ Fixer AI service error: {error_message}")
            return original_response
        
        # Extract and apply fixes
        fix_result = extract_json(raw_content, debug=debug_mode)
        fix_json_str = fix_result.get('extracted_json')
        
        if not fix_json_str:
            print("Warning: Could not extract fixes from fixer response")
            return original_response
        
        fixes_data = json.loads(fix_json_str)
        
        # Apply fixes directly (no separate function)
        fixed_response = json.loads(json.dumps(original_response))  # Deep copy
        
        for fix in fixes_data.get('fixes', []):
            task_index = fix.get('task_index')
            if isinstance(task_index, int) and 0 <= task_index < len(fixed_response.get('tasks', [])):
                # Apply the fixed body
                fixed_response['tasks'][task_index]['body'] = fix.get('fixed_body')
                
                # Note: We no longer need to update meta-validation since we removed Task Reconstruction Verification
                # The programmatic check will handle detection automatically
        
        if debug_mode:
            print(f"Applied fixes to {len(fixes_data.get('fixes', []))} tasks")
        
        return fixed_response
        
    except Exception as e:
        print(f"Error applying claim validation fixes: {e}")
        return original_response


def validate_inputs(data):
    """Validate Required Fields (excluding API keys/model).

    Args:
        data (dict): The input data dictionary (customData).

    Returns:
        str or None: An error message string if validation fails, otherwise None.
    """
    missing_fields = []
    if data is None:
        data = {}

    # Required fields excluding API keys/model now fetched from env
    required_keys = [
        'raw_note',           # Core content for AI processing
        'business_type',      # Essential business context
        'addressed_as',       # Contact personalization
        'recipient_phone',    # SMS URL generation
        'user_first_name',    # User context
        'business_name'       # Business context
    ]

    for field in required_keys:
        value = data.get(field)
        if value is None or value == '':
            missing_fields.append(field)

    if missing_fields:
        return "Missing required fields: " + ", ".join(missing_fields)
    return None



# --- Main Handler Function ---

@https_fn.on_request(
    timeout_sec=3600,
    memory=options.MemoryOption.GB_2,
    region="us-central1",
    secrets=["ANTHROPIC_API_KEY", "GEMINI_API_KEY"]
)
def update_tasks(request: https_fn.Request) -> https_fn.Response:
    """
    HTTP Cloud Function to update tasks based on note content.
    """
    start_time = time.time()
    
    # Initialize the AI service - let it handle secret access internally
    ai_service = get_ai_generation_service()
    
    # --- Webhook validation ---
    if request.method != "POST":
        logger.warning("Received non-POST request")
        return https_fn.Response("Method Not Allowed", status=405)

    # --- Get Request Body ---
    try:
        req_body = request.get_json(silent=True)
        if not req_body or not isinstance(req_body, dict):
             logger.error("Request body is missing or invalid JSON.")
             return https_fn.Response(json.dumps({"success": False, "error": "Request body is missing or invalid JSON."}), status=400, mimetype="application/json")

        logger.info("Webhook received. Processing request...")
        
        data = req_body
        
        request_id = data.get('id')
        callback_url = data.get('callback_url')
        
        if not request_id:
            logger.error("Missing required field: id")
            return https_fn.Response(json.dumps({"success": False, "error": "Missing required field: id"}), status=400, mimetype="application/json")
        
        if not callback_url:
            logger.error("Missing required field: callback_url")
            return https_fn.Response(json.dumps({"success": False, "error": "Missing required field: callback_url"}), status=400, mimetype="application/json")
        
        logger.info(f"🔄 update_tasks Cloud Function started for request {request_id}")
        logger.info(f"🔗 Callback URL: {callback_url}")

        # --- Input Validation ---
        validation_result = validate_inputs(data)
        if validation_result:
            logger.error(f"Input validation failed: {validation_result}")
            error_payload = json.dumps({"success": False, "error": validation_result, "data": None})
            return https_fn.Response(error_payload, status=400, mimetype="application/json")

    except Exception as e:
        logger.error(f"Error processing request body: {e}")
        return https_fn.Response(json.dumps({"success": False, "error": f"Error processing request body: {e}"}), status=400, mimetype="application/json")

    # --- Main Execution Logic ---
    parsed_response = None
    initial_extra_text = None
    status = "processing"
    provider = None
    model = None
    result = None
    try:
        # Note: This code will execute after the HTTP response has been sent

        # --- 2. Input Extraction (API keys/model excluded until needed) ---
        raw_note = data.get('raw_note')
        business_type = data.get('business_type')
        addressed_as = data.get('addressed_as')
        first_name = data.get('first_name', '')
        last_name = data.get('last_name', '')
        email = data.get('email', '')
        recipient_phone = data.get('recipient_phone') 
        user_first_name = data.get('user_first_name')
        # Optional params for prompt generation
        business_name = data.get('business_name')
        follow_up_immediately = data.get('follow_up_immediately', True)  # Enhanced default from migration plan
        relationship_details = data.get('relationship_details', {})
        personal_details = data.get('personal_details', {})
        business_details = data.get('business_details', {})
        language_examples = data.get('language_examples', "")  # Enhanced default
        notes = data.get('subset_notes', [])
        tasks = data.get('subset_tasks', [])
        appointments = data.get('subset_appointments', [])
        # Debug mode
        debug_mode = data.get('debug_mode', False)
        
        # Enhanced thinking configuration from migration plan
        enable_thinking = data.get('enable_thinking')
        if enable_thinking is None:
            # First check environment variable
            env_val = os.environ.get('ENABLE_THINKING')
            if env_val is None:
                # Fall back to Firebase Functions config (project-wide)
                try:
                    from firebase_functions import params
                    env_val = params.get('genai.enable_thinking')
                except Exception:
                    env_val = None
            enable_thinking = str(env_val or 'false').lower() in ('true', '1', 'yes', 'on')

        thinking_budget = data.get('thinking_budget', int(os.environ.get('THINKING_BUDGET_TOKENS', '8000')))

        thinking_config = None
        if enable_thinking:
            thinking_config = {
                "type": "enabled", 
                "budget_tokens": thinking_budget
            }

        # Prepare prompt parameters
        prompt_params = data.copy()
        # Remove keys not needed for prompt generation (already handled or from env)
        keys_to_remove_for_prompt = ['recipient_phone', 'debug_mode']
        for key in keys_to_remove_for_prompt:
            prompt_params.pop(key, None)

        # Generate the prompt
        prompt_data = generatePrompt(prompt_params)
        user_message = prompt_data['userMessage']
        tokens_needed = 12000 # Adjust as needed

        # Prepare messages for AI service
        anthropic_messages = [{"role": "user", "content": user_message}]
        gemini_prompt_text = user_message
        
        logger.info("🧠 Calling AI service for task updates")
        
        # Call AI service using standardized method with thinking configuration
        response_text, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.1,
            max_tokens=tokens_needed,
            thinking_config=thinking_config  # Enhanced: Add thinking configuration
        ))
        
        if error_message:
            logger.error(f"❌ AI service error: {error_message}")
            raise Exception(f"AI generation failed: {error_message}")
        
        raw_content = response_text
        if debug_mode: print("DEBUG - Raw Content:", raw_content)

        # Extract JSON using local utility
        extraction_result = extract_json(raw_content, debug=debug_mode)
        extracted_json_str = extraction_result.get('extracted_json')
        initial_extra_text = extraction_result.get('extra_text')

        if not extracted_json_str:
            logger.error("Failed to extract JSON from Anthropic content.")
            logger.error(f"Raw Content: {raw_content}")
            error_msg = f"Invalid response structure: {initial_extra_text or 'Could not parse JSON from Anthropic response.'}"
            raise Exception(error_msg)

        if debug_mode: print("DEBUG - Extracted JSON Success")

        # Parse JSON with enhanced structure validation
        try:
            parsed_response = json.loads(extracted_json_str)
            if 'analysis_tables' not in parsed_response: parsed_response['analysis_tables'] = {}
            if 'tasks' not in parsed_response: parsed_response['tasks'] = []
            # Enhanced: Support new validation tables from migration plan
            # Only set relationship and topics tables, do not touch task_validation or claim_validation to preserve GenAI output
            for table in ['relationship_table', 'topics_table', 'topics_to_tasks_validation']:
                if table not in parsed_response.get('analysis_tables', {}): 
                    parsed_response['analysis_tables'][table] = []
        except json.JSONDecodeError as jsonError:
            logger.error(f"Error parsing extracted JSON: {jsonError}")
            logger.error(f"Extracted JSON string: {extracted_json_str}")
            raise Exception(f"Invalid JSON structure received from Anthropic: {jsonError}") from jsonError

        parsed_response['extraText'] = initial_extra_text

        # Apply claim validation fixes if needed
        if needs_claim_validation_fixes(parsed_response):
            logger.info("🔧 Applying claim validation fixes...")
            parsed_response = apply_claim_validation_fixes(parsed_response, ai_service, debug_mode)

        # Final Output Construction - Use the modified parsed_response directly with standardized metadata
        processing_time_ms = int((time.time() - start_time) * 1000)
        final_output = {
            "success": True,
            **parsed_response, # Spread the potentially modified parsed_response
            "error": None,
            "llm_provider": provider,  # Provider from AI service
            "llm_model": (ai_service._anthropic_model if provider == "anthropic" 
                         else ai_service._gemini_model_name if provider == "gemini" 
                         else ai_service._openai_model if provider == "openai" 
                         else "unknown"),  # Model from AI service
            "processing_time_ms": processing_time_ms,  # Processing time
            "thinking_enabled": getattr(ai_service, "_last_thinking_enabled", False),
            "thinking_budget_tokens": getattr(ai_service, "_last_thinking_budget", None)
        }
        if 'analysis_tables' not in final_output: final_output['analysis_tables'] = {}
        if 'tasks' not in final_output: final_output['tasks'] = []
        if 'extraText' not in final_output: final_output['extraText'] = None

        if debug_mode:
            print("EXTRACTION SUMMARY:")
            print(f"- analysis_tables: {len(final_output.get('analysis_tables', {}))} tables")
            for name, arr in final_output.get('analysis_tables', {}).items(): print(f"  - {name}: {len(arr) if isinstance(arr, list) else 'N/A'} items")
            print(f"- tasks: {len(final_output.get('tasks', []))} tasks")

        if os.environ.get('INCLUDE_STRINGIFIED_TASKS') == 'true':
            final_output['tasks_stringified'] = json.dumps(final_output.get('tasks', []))
        
        # --- Success Response with Callback ---
        status = "success"
        provider = provider
        model = (ai_service._anthropic_model if provider == "anthropic" 
                else ai_service._gemini_model_name if provider == "gemini" 
                else ai_service._openai_model if provider == "openai" 
                else "unknown")
        result = final_output
        
        success_payload = {
            "id": request_id,
            "request_type": "update_tasks",
            "callback_url": callback_url,
            "success": True,
            "type": "update_tasks",
            **final_output
        }
        
        # Make callback to API
        try:
            import requests
            callback_response = requests.post(
                callback_url,
                json=success_payload,
                timeout=30
            )
            logger.info(f"✅ Callback sent successfully: {callback_response.status_code}")
        except Exception as callback_error:
            logger.error(f"❌ Callback failed: {callback_error}")
        
        logger.info(f"✅ update_tasks completed successfully for request {request_id}")
        return https_fn.Response(json.dumps(success_payload), status=200, mimetype="application/json")
        
    except Exception as error:
        # --- Error Handling with Callback ---
        logger.error(f"Critical error during function execution: {error}")
        error_analysis_tables = {}
        error_tasks = []
        error_extra_text = initial_extra_text
        if parsed_response: # Use data from parsed_response if available
            error_analysis_tables = parsed_response.get('analysis_tables', {})
            error_tasks = parsed_response.get('tasks', [])
            error_extra_text = parsed_response.get('extraText', initial_extra_text)
        
        error_output = {
            "success": False,
            "analysis_tables": error_analysis_tables,
            "tasks": error_tasks,
            "error": f"Operation failed: {str(error) or 'Unknown error'}",
            "extraText": error_extra_text
        }
        
        if data.get('debug_mode', False):
           import traceback
           error_output['debug_info'] = {
               'error_message': str(error),
               'error_type': type(error).__name__,
               'error_traceback': traceback.format_exc()
           }
        
        # Prepare error callback payload
        error_payload = {
            "id": request_id,
            "request_type": "update_tasks", 
            "callback_url": callback_url,
            "success": False,
            "type": "update_tasks",
            "error": str(error)
        }
        
        # Make error callback to API
        try:
            import requests
            callback_response = requests.post(
                callback_url,
                json=error_payload,
                timeout=30
            )
            logger.info(f"✅ Error callback sent successfully: {callback_response.status_code}")
        except Exception as callback_error:
            logger.error(f"❌ Error callback failed: {callback_error}")
        
        logger.error(f"❌ update_tasks failed for request {request_id}: {error}")
        return https_fn.Response(json.dumps(error_payload), status=500, mimetype="application/json")
        
    finally:
        # Monitoring/metrics logging
        try:
            completed_at = time.time()
            duration_ms = int((completed_at - start_time) * 1000)
            
            logger.info(f"🔄 update_tasks completed - Status: {status}, Duration: {duration_ms}ms")
            if provider:
                logger.info(f"🤖 Provider: {provider}, Model: {model}")
            if result:
                logger.info(f"📊 Result size: {len(json.dumps(result))} chars")
        except Exception as monitoring_error:
            logger.error(f"Monitoring error: {monitoring_error}")
