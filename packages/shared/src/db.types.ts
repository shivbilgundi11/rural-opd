/**
 * GENERATED FILE - DO NOT EDIT BY HAND.
 *
 * Regenerate with the local Supabase stack running:
 *
 *     pnpm db:start
 *     pnpm db:types
 *
 * This is the single source of truth for every table row, insert, update and
 * enum in the product. Nothing anywhere re-declares a database enum by hand --
 * a hand-written enum is how a client invents a status the database never
 * emits (DESIGN.md section 5, docs/CONVENTIONS.md section 5).
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      appointment_transitions: {
        Row: {
          from_status: Database["public"]["Enums"]["appointment_status"]
          to_status: Database["public"]["Enums"]["appointment_status"]
        }
        Insert: {
          from_status: Database["public"]["Enums"]["appointment_status"]
          to_status: Database["public"]["Enums"]["appointment_status"]
        }
        Update: {
          from_status?: Database["public"]["Enums"]["appointment_status"]
          to_status?: Database["public"]["Enums"]["appointment_status"]
        }
        Relationships: []
      }
      appointments: {
        Row: {
          booked_by_auth_user_id: string | null
          cancel_reason: string | null
          cancelled_at: string | null
          chief_complaint: string | null
          confirmed_at: string | null
          created_at: string
          currency: string
          doctor_id: string
          expires_at: string | null
          fee_amount_paise: number
          hospital_id: string
          id: string
          patient_id: string
          session_id: string
          source: Database["public"]["Enums"]["appointment_source"]
          status: Database["public"]["Enums"]["appointment_status"]
          updated_at: string
        }
        Insert: {
          booked_by_auth_user_id?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          chief_complaint?: string | null
          confirmed_at?: string | null
          created_at?: string
          currency?: string
          doctor_id: string
          expires_at?: string | null
          fee_amount_paise: number
          hospital_id: string
          id?: string
          patient_id: string
          session_id: string
          source?: Database["public"]["Enums"]["appointment_source"]
          status?: Database["public"]["Enums"]["appointment_status"]
          updated_at?: string
        }
        Update: {
          booked_by_auth_user_id?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          chief_complaint?: string | null
          confirmed_at?: string | null
          created_at?: string
          currency?: string
          doctor_id?: string
          expires_at?: string | null
          fee_amount_paise?: number
          hospital_id?: string
          id?: string
          patient_id?: string
          session_id?: string
          source?: Database["public"]["Enums"]["appointment_source"]
          status?: Database["public"]["Enums"]["appointment_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "appointments_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "appointments_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
          {
            foreignKeyName: "appointments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "opd_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "appointments_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_queue_snapshot"
            referencedColumns: ["session_id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_auth_user_id: string | null
          actor_role: string | null
          after_row: Json | null
          before_row: Json | null
          created_at: string
          id: number
          row_id: string
          table_name: string
        }
        Insert: {
          action: string
          actor_auth_user_id?: string | null
          actor_role?: string | null
          after_row?: Json | null
          before_row?: Json | null
          created_at?: string
          id?: number
          row_id: string
          table_name: string
        }
        Update: {
          action?: string
          actor_auth_user_id?: string | null
          actor_role?: string | null
          after_row?: Json | null
          before_row?: Json | null
          created_at?: string
          id?: number
          row_id?: string
          table_name?: string
        }
        Relationships: []
      }
      device_push_tokens: {
        Row: {
          auth_user_id: string
          created_at: string
          expo_push_token: string
          id: string
          last_seen_at: string
          platform: string
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          expo_push_token: string
          id?: string
          last_seen_at?: string
          platform: string
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          expo_push_token?: string
          id?: string
          last_seen_at?: string
          platform?: string
        }
        Relationships: []
      }
      doctors: {
        Row: {
          consultation_fee_paise: number
          created_at: string
          full_name: string
          hospital_id: string
          id: string
          image_path: string | null
          is_active: boolean
          qualification: string | null
          registration_no: string | null
          specialty: string
          staff_user_id: string | null
          updated_at: string
        }
        Insert: {
          consultation_fee_paise: number
          created_at?: string
          full_name: string
          hospital_id: string
          id?: string
          image_path?: string | null
          is_active?: boolean
          qualification?: string | null
          registration_no?: string | null
          specialty: string
          staff_user_id?: string | null
          updated_at?: string
        }
        Update: {
          consultation_fee_paise?: number
          created_at?: string
          full_name?: string
          hospital_id?: string
          id?: string
          image_path?: string | null
          is_active?: boolean
          qualification?: string | null
          registration_no?: string | null
          specialty?: string
          staff_user_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "doctors_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "doctors_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
          {
            foreignKeyName: "doctors_staff_user_id_fkey"
            columns: ["staff_user_id"]
            isOneToOne: false
            referencedRelation: "staff_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      follow_ups: {
        Row: {
          booked_appointment_id: string | null
          created_at: string
          created_by_auth_user_id: string | null
          doctor_id: string | null
          due_date: string
          hospital_id: string
          id: string
          notes: string | null
          patient_id: string
          source_appointment_id: string
          status: Database["public"]["Enums"]["follow_up_status"]
          updated_at: string
        }
        Insert: {
          booked_appointment_id?: string | null
          created_at?: string
          created_by_auth_user_id?: string | null
          doctor_id?: string | null
          due_date: string
          hospital_id: string
          id?: string
          notes?: string | null
          patient_id: string
          source_appointment_id: string
          status?: Database["public"]["Enums"]["follow_up_status"]
          updated_at?: string
        }
        Update: {
          booked_appointment_id?: string | null
          created_at?: string
          created_by_auth_user_id?: string | null
          doctor_id?: string | null
          due_date?: string
          hospital_id?: string
          id?: string
          notes?: string | null
          patient_id?: string
          source_appointment_id?: string
          status?: Database["public"]["Enums"]["follow_up_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "follow_ups_booked_appointment_id_fkey"
            columns: ["booked_appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follow_ups_booked_appointment_id_fkey"
            columns: ["booked_appointment_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
          {
            foreignKeyName: "follow_ups_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follow_ups_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "follow_ups_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follow_ups_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
          {
            foreignKeyName: "follow_ups_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follow_ups_source_appointment_id_fkey"
            columns: ["source_appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follow_ups_source_appointment_id_fkey"
            columns: ["source_appointment_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
        ]
      }
      hospitals: {
        Row: {
          address_line: string | null
          city: string | null
          created_at: string
          district: string | null
          id: string
          image_path: string | null
          is_active: boolean
          latitude: number | null
          longitude: number | null
          name: string
          phone: string | null
          pincode: string | null
          slug: string
          state: string | null
          timezone: string
          updated_at: string
        }
        Insert: {
          address_line?: string | null
          city?: string | null
          created_at?: string
          district?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name: string
          phone?: string | null
          pincode?: string | null
          slug: string
          state?: string | null
          timezone?: string
          updated_at?: string
        }
        Update: {
          address_line?: string | null
          city?: string | null
          created_at?: string
          district?: string | null
          id?: string
          image_path?: string | null
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name?: string
          phone?: string | null
          pincode?: string | null
          slug?: string
          state?: string | null
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      medical_profiles: {
        Row: {
          allergies: string[]
          blood_group: string | null
          conditions: string[]
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          medications: string[]
          patient_id: string
          updated_at: string
        }
        Insert: {
          allergies?: string[]
          blood_group?: string | null
          conditions?: string[]
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          medications?: string[]
          patient_id: string
          updated_at?: string
        }
        Update: {
          allergies?: string[]
          blood_group?: string | null
          conditions?: string[]
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          medications?: string[]
          patient_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "medical_profiles_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: true
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_deliveries: {
        Row: {
          attempted_at: string
          channel: Database["public"]["Enums"]["notification_channel"]
          error_code: string | null
          error_detail: string | null
          id: number
          outbox_id: string
          provider: string | null
          provider_message_id: string | null
          succeeded: boolean
        }
        Insert: {
          attempted_at?: string
          channel: Database["public"]["Enums"]["notification_channel"]
          error_code?: string | null
          error_detail?: string | null
          id?: number
          outbox_id: string
          provider?: string | null
          provider_message_id?: string | null
          succeeded: boolean
        }
        Update: {
          attempted_at?: string
          channel?: Database["public"]["Enums"]["notification_channel"]
          error_code?: string | null
          error_detail?: string | null
          id?: number
          outbox_id?: string
          provider?: string | null
          provider_message_id?: string | null
          succeeded?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "notification_deliveries_outbox_id_fkey"
            columns: ["outbox_id"]
            isOneToOne: false
            referencedRelation: "notification_outbox"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_outbox: {
        Row: {
          appointment_id: string | null
          attempts: number
          channels: Database["public"]["Enums"]["notification_channel"][]
          created_at: string
          dedupe_key: string
          id: string
          last_error: string | null
          next_attempt_at: string
          payload: Json
          recipient_auth_user_id: string | null
          sent_at: string | null
          session_id: string | null
          status: Database["public"]["Enums"]["outbox_status"]
          template_key: string
          token_id: string | null
          updated_at: string
        }
        Insert: {
          appointment_id?: string | null
          attempts?: number
          channels?: Database["public"]["Enums"]["notification_channel"][]
          created_at?: string
          dedupe_key: string
          id?: string
          last_error?: string | null
          next_attempt_at?: string
          payload?: Json
          recipient_auth_user_id?: string | null
          sent_at?: string | null
          session_id?: string | null
          status?: Database["public"]["Enums"]["outbox_status"]
          template_key: string
          token_id?: string | null
          updated_at?: string
        }
        Update: {
          appointment_id?: string | null
          attempts?: number
          channels?: Database["public"]["Enums"]["notification_channel"][]
          created_at?: string
          dedupe_key?: string
          id?: string
          last_error?: string | null
          next_attempt_at?: string
          payload?: Json
          recipient_auth_user_id?: string | null
          sent_at?: string | null
          session_id?: string | null
          status?: Database["public"]["Enums"]["outbox_status"]
          template_key?: string
          token_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_outbox_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_outbox_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
          {
            foreignKeyName: "notification_outbox_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "opd_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_outbox_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "notification_outbox_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_queue_snapshot"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "notification_outbox_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "opd_tokens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_outbox_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["token_id"]
          },
          {
            foreignKeyName: "notification_outbox_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "v_queue_positions"
            referencedColumns: ["token_id"]
          },
        ]
      }
      opd_sessions: {
        Row: {
          avg_consult_minutes: number
          capacity: number
          created_at: string
          current_token_number: number
          doctor_id: string
          end_time: string
          hospital_id: string
          id: string
          last_token_number: number
          session_date: string
          start_time: string
          status: Database["public"]["Enums"]["session_status"]
          updated_at: string
        }
        Insert: {
          avg_consult_minutes?: number
          capacity: number
          created_at?: string
          current_token_number?: number
          doctor_id: string
          end_time: string
          hospital_id: string
          id?: string
          last_token_number?: number
          session_date: string
          start_time: string
          status?: Database["public"]["Enums"]["session_status"]
          updated_at?: string
        }
        Update: {
          avg_consult_minutes?: number
          capacity?: number
          created_at?: string
          current_token_number?: number
          doctor_id?: string
          end_time?: string
          hospital_id?: string
          id?: string
          last_token_number?: number
          session_date?: string
          start_time?: string
          status?: Database["public"]["Enums"]["session_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "opd_sessions_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_sessions_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "opd_sessions_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_sessions_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
        ]
      }
      opd_tokens: {
        Row: {
          appointment_id: string
          called_at: string | null
          completed_at: string | null
          consultation_started_at: string | null
          doctor_id: string
          hospital_id: string
          id: string
          issued_at: string
          patient_id: string
          recall_count: number
          session_id: string
          status: Database["public"]["Enums"]["token_status"]
          token_number: number
        }
        Insert: {
          appointment_id: string
          called_at?: string | null
          completed_at?: string | null
          consultation_started_at?: string | null
          doctor_id: string
          hospital_id: string
          id?: string
          issued_at?: string
          patient_id: string
          recall_count?: number
          session_id: string
          status?: Database["public"]["Enums"]["token_status"]
          token_number: number
        }
        Update: {
          appointment_id?: string
          called_at?: string | null
          completed_at?: string | null
          consultation_started_at?: string | null
          doctor_id?: string
          hospital_id?: string
          id?: string
          issued_at?: string
          patient_id?: string
          recall_count?: number
          session_id?: string
          status?: Database["public"]["Enums"]["token_status"]
          token_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "opd_tokens_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: true
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: true
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
          {
            foreignKeyName: "opd_tokens_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "opd_tokens_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
          {
            foreignKeyName: "opd_tokens_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "opd_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_queue_snapshot"
            referencedColumns: ["session_id"]
          },
        ]
      }
      patient_family_links: {
        Row: {
          created_at: string
          id: string
          owner_auth_user_id: string
          patient_id: string
          relationship: string
        }
        Insert: {
          created_at?: string
          id?: string
          owner_auth_user_id: string
          patient_id: string
          relationship: string
        }
        Update: {
          created_at?: string
          id?: string
          owner_auth_user_id?: string
          patient_id?: string
          relationship?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_family_links_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      patients: {
        Row: {
          auth_user_id: string | null
          created_at: string
          created_by_auth_user_id: string | null
          date_of_birth: string | null
          email: string | null
          full_name: string
          gender: string | null
          id: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string
          created_by_auth_user_id?: string | null
          date_of_birth?: string | null
          email?: string | null
          full_name: string
          gender?: string | null
          id?: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string
          created_by_auth_user_id?: string | null
          date_of_birth?: string | null
          email?: string | null
          full_name?: string
          gender?: string | null
          id?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      payment_webhook_events: {
        Row: {
          created_at: string
          event_id: string
          event_type: string
          gateway: string
          id: string
          payload: Json
          processed_at: string | null
          processing_result: string | null
          signature_valid: boolean
        }
        Insert: {
          created_at?: string
          event_id: string
          event_type: string
          gateway: string
          id?: string
          payload: Json
          processed_at?: string | null
          processing_result?: string | null
          signature_valid: boolean
        }
        Update: {
          created_at?: string
          event_id?: string
          event_type?: string
          gateway?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          processing_result?: string | null
          signature_valid?: boolean
        }
        Relationships: []
      }
      payments: {
        Row: {
          amount_paise: number
          appointment_id: string
          created_at: string
          currency: string
          failure_code: string | null
          failure_reason: string | null
          gateway: string
          gateway_order_id: string
          gateway_payment_id: string | null
          id: string
          method: string | null
          raw_payload: Json | null
          refunded_at: string | null
          status: Database["public"]["Enums"]["payment_status"]
          updated_at: string
          verified_at: string | null
        }
        Insert: {
          amount_paise: number
          appointment_id: string
          created_at?: string
          currency?: string
          failure_code?: string | null
          failure_reason?: string | null
          gateway: string
          gateway_order_id: string
          gateway_payment_id?: string | null
          id?: string
          method?: string | null
          raw_payload?: Json | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          updated_at?: string
          verified_at?: string | null
        }
        Update: {
          amount_paise?: number
          appointment_id?: string
          created_at?: string
          currency?: string
          failure_code?: string | null
          failure_reason?: string | null
          gateway?: string
          gateway_order_id?: string
          gateway_payment_id?: string | null
          id?: string
          method?: string | null
          raw_payload?: Json | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          updated_at?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payments_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
        ]
      }
      queue_events: {
        Row: {
          actor_auth_user_id: string | null
          actor_role: string | null
          appointment_id: string | null
          created_at: string
          event_type: Database["public"]["Enums"]["queue_event_type"]
          from_status: string | null
          id: number
          metadata: Json
          session_id: string
          to_status: string | null
          token_id: string | null
        }
        Insert: {
          actor_auth_user_id?: string | null
          actor_role?: string | null
          appointment_id?: string | null
          created_at?: string
          event_type: Database["public"]["Enums"]["queue_event_type"]
          from_status?: string | null
          id?: number
          metadata?: Json
          session_id: string
          to_status?: string | null
          token_id?: string | null
        }
        Update: {
          actor_auth_user_id?: string | null
          actor_role?: string | null
          appointment_id?: string | null
          created_at?: string
          event_type?: Database["public"]["Enums"]["queue_event_type"]
          from_status?: string | null
          id?: number
          metadata?: Json
          session_id?: string
          to_status?: string | null
          token_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "queue_events_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "queue_events_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
          {
            foreignKeyName: "queue_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "opd_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "queue_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "queue_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_queue_snapshot"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "queue_events_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "opd_tokens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "queue_events_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["token_id"]
          },
          {
            foreignKeyName: "queue_events_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "v_queue_positions"
            referencedColumns: ["token_id"]
          },
        ]
      }
      staff_profiles: {
        Row: {
          created_at: string
          full_name: string
          hospital_id: string | null
          id: string
          is_active: boolean
          phone: string | null
          role: Database["public"]["Enums"]["staff_role"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          full_name: string
          hospital_id?: string | null
          id: string
          is_active?: boolean
          phone?: string | null
          role: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          full_name?: string
          hospital_id?: string | null
          id?: string
          is_active?: boolean
          phone?: string | null
          role?: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_profiles_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_profiles_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
        ]
      }
      token_transitions: {
        Row: {
          from_status: Database["public"]["Enums"]["token_status"]
          to_status: Database["public"]["Enums"]["token_status"]
        }
        Insert: {
          from_status: Database["public"]["Enums"]["token_status"]
          to_status: Database["public"]["Enums"]["token_status"]
        }
        Update: {
          from_status?: Database["public"]["Enums"]["token_status"]
          to_status?: Database["public"]["Enums"]["token_status"]
        }
        Relationships: []
      }
    }
    Views: {
      v_patient_appointments: {
        Row: {
          appointment_id: string | null
          appointment_status:
            | Database["public"]["Enums"]["appointment_status"]
            | null
          avg_consult_minutes: number | null
          booked_by_auth_user_id: string | null
          cancelled_at: string | null
          chief_complaint: string | null
          confirmed_at: string | null
          created_at: string | null
          currency: string | null
          current_token_number: number | null
          doctor_id: string | null
          doctor_name: string | null
          doctor_specialty: string | null
          end_time: string | null
          expires_at: string | null
          fee_amount_paise: number | null
          hospital_city: string | null
          hospital_id: string | null
          hospital_name: string | null
          hospital_timezone: string | null
          patient_id: string | null
          patient_name: string | null
          session_date: string | null
          session_id: string | null
          session_status: Database["public"]["Enums"]["session_status"] | null
          source: Database["public"]["Enums"]["appointment_source"] | null
          start_time: string | null
          token_id: string | null
          token_issued_at: string | null
          token_number: number | null
          token_status: Database["public"]["Enums"]["token_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "appointments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      v_queue_positions: {
        Row: {
          appointment_id: string | null
          avg_consult_minutes: number | null
          doctor_id: string | null
          hospital_id: string | null
          patient_id: string | null
          people_ahead: number | null
          position_in_queue: number | null
          session_id: string | null
          status: Database["public"]["Enums"]["token_status"] | null
          token_id: string | null
          token_number: number | null
        }
        Relationships: [
          {
            foreignKeyName: "opd_tokens_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: true
            referencedRelation: "appointments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_appointment_id_fkey"
            columns: ["appointment_id"]
            isOneToOne: true
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["appointment_id"]
          },
          {
            foreignKeyName: "opd_tokens_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "opd_tokens_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
          {
            foreignKeyName: "opd_tokens_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "opd_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["session_id"]
          },
          {
            foreignKeyName: "opd_tokens_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "v_queue_snapshot"
            referencedColumns: ["session_id"]
          },
        ]
      }
      v_queue_snapshot: {
        Row: {
          avg_consult_minutes: number | null
          called_count: number | null
          capacity: number | null
          completed_count: number | null
          current_token_number: number | null
          doctor_id: string | null
          end_time: string | null
          hospital_id: string | null
          in_consultation_count: number | null
          last_issued_number: number | null
          last_token_number: number | null
          no_show_count: number | null
          recalled_count: number | null
          session_date: string | null
          session_id: string | null
          session_status: Database["public"]["Enums"]["session_status"] | null
          skipped_count: number | null
          snapshot_at: string | null
          start_time: string | null
          waiting_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "opd_sessions_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "doctors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_sessions_doctor_id_fkey"
            columns: ["doctor_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["doctor_id"]
          },
          {
            foreignKeyName: "opd_sessions_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "hospitals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opd_sessions_hospital_id_fkey"
            columns: ["hospital_id"]
            isOneToOne: false
            referencedRelation: "v_patient_appointments"
            referencedColumns: ["hospital_id"]
          },
        ]
      }
    }
    Functions: {
      admin_read_medical_profile: {
        Args: { p_patient: string }
        Returns: {
          allergies: string[]
          blood_group: string | null
          conditions: string[]
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          medications: string[]
          patient_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "medical_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      appointment_hospital_id: {
        Args: { p_appointment: string }
        Returns: string
      }
      appointment_ids_for_current_user: { Args: never; Returns: string[] }
      auth_aal: { Args: never; Returns: string }
      auth_uid: { Args: never; Returns: string }
      doctor_id_for_current_user: { Args: never; Returns: string }
      doctor_is_bookable: { Args: { p_doctor: string }; Returns: boolean }
      doctor_owns_session: { Args: { p_session: string }; Returns: boolean }
      hospital_is_active: { Args: { p_hospital: string }; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      next_token_number: { Args: { p_session_id: string }; Returns: number }
      patient_has_appointment_at: {
        Args: { p_hospital: string; p_patient: string }
        Returns: boolean
      }
      patient_ids_for_current_user: { Args: never; Returns: string[] }
      patient_in_doctor_consultation: {
        Args: { p_patient: string }
        Returns: boolean
      }
      patient_in_doctor_queue: { Args: { p_patient: string }; Returns: boolean }
      session_hospital_id: { Args: { p_session: string }; Returns: string }
      staff_hospital_id: { Args: never; Returns: string }
      staff_mfa_satisfied: { Args: never; Returns: boolean }
      staff_role: {
        Args: never
        Returns: Database["public"]["Enums"]["staff_role"]
      }
      token_ids_for_current_user: { Args: never; Returns: string[] }
    }
    Enums: {
      appointment_source: "APP" | "WALK_IN"
      appointment_status:
        | "DRAFT"
        | "PENDING_PAYMENT"
        | "PAYMENT_PROCESSING"
        | "CONFIRMED"
        | "TOKEN_GENERATED"
        | "CHECKED_IN"
        | "WAITING"
        | "IN_CONSULTATION"
        | "COMPLETED"
        | "PAYMENT_FAILED"
        | "EXPIRED"
        | "CANCELLED"
        | "NO_SHOW"
      follow_up_status: "PENDING" | "SCHEDULED" | "COMPLETED" | "CANCELLED"
      notification_channel: "PUSH" | "SMS" | "WHATSAPP"
      outbox_status: "PENDING" | "SENDING" | "SENT" | "FAILED" | "DEAD"
      payment_status:
        | "CREATED"
        | "PROCESSING"
        | "SUCCESS"
        | "FAILED"
        | "REFUNDED"
      queue_event_type:
        | "TOKEN_CREATED"
        | "CHECKED_IN"
        | "CALLED"
        | "RECALLED"
        | "SKIPPED"
        | "CONSULT_STARTED"
        | "CONSULT_COMPLETED"
        | "NO_SHOW"
        | "CANCELLED"
      session_status: "SCHEDULED" | "ACTIVE" | "PAUSED" | "CLOSED" | "CANCELLED"
      staff_role: "DOCTOR" | "RECEPTIONIST" | "HOSPITAL_ADMIN" | "SUPER_ADMIN"
      token_status:
        | "WAITING"
        | "CALLED"
        | "RECALLED"
        | "SKIPPED"
        | "IN_CONSULTATION"
        | "COMPLETED"
        | "NO_SHOW"
        | "CANCELLED"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      appointment_source: ["APP", "WALK_IN"],
      appointment_status: [
        "DRAFT",
        "PENDING_PAYMENT",
        "PAYMENT_PROCESSING",
        "CONFIRMED",
        "TOKEN_GENERATED",
        "CHECKED_IN",
        "WAITING",
        "IN_CONSULTATION",
        "COMPLETED",
        "PAYMENT_FAILED",
        "EXPIRED",
        "CANCELLED",
        "NO_SHOW",
      ],
      follow_up_status: ["PENDING", "SCHEDULED", "COMPLETED", "CANCELLED"],
      notification_channel: ["PUSH", "SMS", "WHATSAPP"],
      outbox_status: ["PENDING", "SENDING", "SENT", "FAILED", "DEAD"],
      payment_status: [
        "CREATED",
        "PROCESSING",
        "SUCCESS",
        "FAILED",
        "REFUNDED",
      ],
      queue_event_type: [
        "TOKEN_CREATED",
        "CHECKED_IN",
        "CALLED",
        "RECALLED",
        "SKIPPED",
        "CONSULT_STARTED",
        "CONSULT_COMPLETED",
        "NO_SHOW",
        "CANCELLED",
      ],
      session_status: ["SCHEDULED", "ACTIVE", "PAUSED", "CLOSED", "CANCELLED"],
      staff_role: ["DOCTOR", "RECEPTIONIST", "HOSPITAL_ADMIN", "SUPER_ADMIN"],
      token_status: [
        "WAITING",
        "CALLED",
        "RECALLED",
        "SKIPPED",
        "IN_CONSULTATION",
        "COMPLETED",
        "NO_SHOW",
        "CANCELLED",
      ],
    },
  },
} as const

/** Convenience alias for the schema the clients actually talk to. */
export type PublicSchema = Database["public"];
