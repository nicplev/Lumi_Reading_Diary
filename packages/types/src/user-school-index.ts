export interface UserSchoolIndex {
  id: string;
  userId: string;
  email: string;
  schools: Record<
    string,
    {
      role: string;
      schoolName: string;
    }
  >;
}
