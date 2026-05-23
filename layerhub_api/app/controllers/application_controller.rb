class ApplicationController < ActionController::API
  before_action :authenticate_user!

  private

  def current_project
    @current_project ||= current_user.projects.find(params[:project_id])
  end
end
